// SPDX-License-Identifier: GPL-2.0-only
/*
 * Awinic AW8622x (AW86223/AW86224/AW86225) LRA haptic driver, continuous mode.
 *
 * Written for the Razer Edge (nicole). The register layout and the continuous
 * ("CONT") play sequence follow Razer's vendor driver (drivers/misc/haptic_nv,
 * aw862xx.c: aw862xx_cont_config(), aw862xx_play_stop()). Mainline aw86927.c
 * does not cover this family: the registers differ at 0x2d/0x2e and 0x48.
 *
 * CONT mode drives the LRA at its resonance (f0 tracking in the chip), so no
 * waveform has to be uploaded: a rumble effect starts it with a drive level
 * from the effect's magnitude, input-ff-memless stops it when the effect ends.
 * The sequence was first proven from user space over i2c-dev (30 Ekim 2026).
 */

#include <linux/bitfield.h>
#include <linux/bits.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regmap.h>

#define AW8622X_ID_REG			0x00
#define AW8622X_CHIPID			0x00

#define AW8622X_PLAYCFG3_REG		0x08
#define AW8622X_PLAYCFG3_BRK_EN		BIT(2)
#define AW8622X_PLAYCFG3_PLAY_MODE	GENMASK(1, 0)
#define AW8622X_PLAYCFG3_MODE_RAM	0
#define AW8622X_PLAYCFG3_MODE_CONT	2

#define AW8622X_PLAYCFG4_REG		0x09
#define AW8622X_PLAYCFG4_STOP		BIT(1)
#define AW8622X_PLAYCFG4_GO		BIT(0)

#define AW8622X_CONTCFG6_REG		0x1d
#define AW8622X_CONTCFG6_TRACK_EN	BIT(7)
#define AW8622X_CONTCFG6_DRV1_LVL	GENMASK(6, 0)
#define AW8622X_CONTCFG7_REG		0x1e	/* DRV2 level */
#define AW8622X_CONTCFG9_REG		0x20	/* DRV2 time, 0xff: until stopped */
#define AW8622X_CONTCFG13_REG		0x24
#define AW8622X_CONTCFG13_TSET		GENMASK(7, 4)
#define AW8622X_CONTCFG13_BEMF_SET	GENMASK(3, 0)

#define AW8622X_GLBRD5_REG		0x3f
#define AW8622X_GLBRD5_STATE		GENMASK(3, 0)
#define AW8622X_STATE_STANDBY		0
#define AW8622X_STATE_BRAKE		11

#define AW8622X_SYSCTRL3_REG		0x45	/* SIN_H, SIN_L, COS_H, COS_L */
#define AW8622X_MAX_REG			0x7f

/* Razer's tuning for nicole's LRA (lahainap-nicole.dtsi, haptic_nv@5A) */
#define AW8622X_DRV1_LVL_MAX		0x7f
#define AW8622X_DRV2_LVL_MAX		0x4e
#define AW8622X_CONT_TSET		0x6
#define AW8622X_CONT_BEMF_SET		0x2
static const u8 aw8622x_sine_array[] = { 0x05, 0xb2, 0xff, 0xef };

struct aw8622x {
	struct device *dev;
	struct regmap *regmap;
	struct input_dev *input;
	struct gpio_desc *reset_gpio;
	struct work_struct play_work;
	u16 level;	/* 0 = stop */
};

static const struct regmap_config aw8622x_regmap_config = {
	.reg_bits = 8,
	.val_bits = 8,
	.max_register = AW8622X_MAX_REG,
	.cache_type = REGCACHE_NONE,
};

static int aw8622x_stop(struct aw8622x *hap)
{
	unsigned int state;
	int err;

	err = regmap_write(hap->regmap, AW8622X_PLAYCFG4_REG, AW8622X_PLAYCFG4_STOP);
	if (err)
		return err;

	/* The chip brakes, then falls back to standby (a few ms) */
	return regmap_read_poll_timeout(hap->regmap, AW8622X_GLBRD5_REG, state,
					FIELD_GET(AW8622X_GLBRD5_STATE, state) ==
						AW8622X_STATE_STANDBY ||
					FIELD_GET(AW8622X_GLBRD5_STATE, state) ==
						AW8622X_STATE_BRAKE,
					2000, 80000);
}

static int aw8622x_play(struct aw8622x *hap, u16 level)
{
	u8 drv1, drv2;
	int err;

	drv1 = max_t(u8, 1, DIV_ROUND_UP(level * AW8622X_DRV1_LVL_MAX, 0xffff));
	drv2 = max_t(u8, 1, DIV_ROUND_UP(level * AW8622X_DRV2_LVL_MAX, 0xffff));

	err = regmap_update_bits(hap->regmap, AW8622X_PLAYCFG3_REG,
				 AW8622X_PLAYCFG3_PLAY_MODE,
				 FIELD_PREP(AW8622X_PLAYCFG3_PLAY_MODE,
					    AW8622X_PLAYCFG3_MODE_CONT));
	if (err)
		return err;

	err = regmap_write(hap->regmap, AW8622X_CONTCFG6_REG,
			   AW8622X_CONTCFG6_TRACK_EN |
			   FIELD_PREP(AW8622X_CONTCFG6_DRV1_LVL, drv1));
	if (err)
		return err;

	err = regmap_write(hap->regmap, AW8622X_CONTCFG7_REG, drv2);
	if (err)
		return err;

	err = regmap_write(hap->regmap, AW8622X_CONTCFG9_REG, 0xff);
	if (err)
		return err;

	return regmap_write(hap->regmap, AW8622X_PLAYCFG4_REG, AW8622X_PLAYCFG4_GO);
}

static void aw8622x_play_work(struct work_struct *work)
{
	struct aw8622x *hap = container_of(work, struct aw8622x, play_work);
	int err;

	err = aw8622x_stop(hap);
	if (err)
		dev_err(hap->dev, "failed to stop: %d\n", err);

	if (hap->level) {
		err = aw8622x_play(hap, hap->level);
		if (err)
			dev_err(hap->dev, "failed to play: %d\n", err);
	}
}

static int aw8622x_play_effect(struct input_dev *input, void *data,
			       struct ff_effect *effect)
{
	struct aw8622x *hap = input_get_drvdata(input);
	u32 level;

	if (effect->type != FF_RUMBLE)
		return 0;

	/* Weak (high frequency) motor counts half, as in other rumble drivers */
	level = max_t(u32, effect->u.rumble.strong_magnitude,
		      effect->u.rumble.weak_magnitude / 2);
	hap->level = level;
	schedule_work(&hap->play_work);

	return 0;
}

static void aw8622x_close(struct input_dev *input)
{
	struct aw8622x *hap = input_get_drvdata(input);

	cancel_work_sync(&hap->play_work);
	hap->level = 0;
	aw8622x_stop(hap);
}

static int aw8622x_hw_init(struct aw8622x *hap)
{
	int err;

	if (hap->reset_gpio) {
		/* Active-high reset pulse, as the vendor driver does it */
		gpiod_set_value_cansleep(hap->reset_gpio, 1);
		usleep_range(2000, 3000);
		gpiod_set_value_cansleep(hap->reset_gpio, 0);
		usleep_range(8000, 8500);
	}

	err = regmap_bulk_write(hap->regmap, AW8622X_SYSCTRL3_REG,
				aw8622x_sine_array, ARRAY_SIZE(aw8622x_sine_array));
	if (err)
		return err;

	err = regmap_update_bits(hap->regmap, AW8622X_CONTCFG13_REG,
				 AW8622X_CONTCFG13_TSET | AW8622X_CONTCFG13_BEMF_SET,
				 FIELD_PREP(AW8622X_CONTCFG13_TSET, AW8622X_CONT_TSET) |
				 FIELD_PREP(AW8622X_CONTCFG13_BEMF_SET,
					    AW8622X_CONT_BEMF_SET));
	if (err)
		return err;

	/* Brake after every effect, RAM mode as the idle setting */
	err = regmap_update_bits(hap->regmap, AW8622X_PLAYCFG3_REG,
				 AW8622X_PLAYCFG3_BRK_EN | AW8622X_PLAYCFG3_PLAY_MODE,
				 AW8622X_PLAYCFG3_BRK_EN |
				 FIELD_PREP(AW8622X_PLAYCFG3_PLAY_MODE,
					    AW8622X_PLAYCFG3_MODE_RAM));
	if (err)
		return err;

	return aw8622x_stop(hap);
}

static int aw8622x_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct aw8622x *hap;
	unsigned int id;
	int err;

	hap = devm_kzalloc(dev, sizeof(*hap), GFP_KERNEL);
	if (!hap)
		return -ENOMEM;

	hap->dev = dev;
	INIT_WORK(&hap->play_work, aw8622x_play_work);

	hap->regmap = devm_regmap_init_i2c(client, &aw8622x_regmap_config);
	if (IS_ERR(hap->regmap))
		return dev_err_probe(dev, PTR_ERR(hap->regmap), "regmap init failed\n");

	hap->reset_gpio = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(hap->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(hap->reset_gpio),
				     "failed to get reset gpio\n");

	err = regmap_read(hap->regmap, AW8622X_ID_REG, &id);
	if (err)
		return dev_err_probe(dev, err, "failed to read chip id\n");
	if (id != AW8622X_CHIPID)
		return dev_err_probe(dev, -ENODEV, "unexpected chip id 0x%02x\n", id);

	err = aw8622x_hw_init(hap);
	if (err)
		return dev_err_probe(dev, err, "init failed\n");

	hap->input = devm_input_allocate_device(dev);
	if (!hap->input)
		return -ENOMEM;

	hap->input->name = "aw8622x-haptics";
	hap->input->close = aw8622x_close;
	input_set_drvdata(hap->input, hap);
	input_set_capability(hap->input, EV_FF, FF_RUMBLE);

	err = input_ff_create_memless(hap->input, NULL, aw8622x_play_effect);
	if (err)
		return dev_err_probe(dev, err, "failed to create FF device\n");

	err = input_register_device(hap->input);
	if (err)
		return dev_err_probe(dev, err, "failed to register input device\n");

	return 0;
}

static const struct of_device_id aw8622x_of_match[] = {
	{ .compatible = "awinic,aw8622x" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, aw8622x_of_match);

/* Also bindable by hand: echo aw8622x 0x58 > /sys/bus/i2c/devices/i2c-N/new_device */
static const struct i2c_device_id aw8622x_id[] = {
	{ "aw8622x" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(i2c, aw8622x_id);

static struct i2c_driver aw8622x_driver = {
	.driver = {
		.name = "aw8622x-haptics",
		.of_match_table = aw8622x_of_match,
	},
	.probe = aw8622x_probe,
	.id_table = aw8622x_id,
};
module_i2c_driver(aw8622x_driver);

MODULE_DESCRIPTION("Awinic AW8622x LRA haptic driver (continuous mode)");
MODULE_LICENSE("GPL");
