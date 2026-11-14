// SPDX-License-Identifier: GPL-2.0-only
/*
 * FocalTech FT3658S SPI touchscreen controller driver
 *
 * The SPI framing, register map and report format were derived from the
 * FocalTech "focaltech_touch_spi" vendor driver (V3.4 20211214) shipped in
 * the Razer Edge (nicole) Android kernel.
 *
 * SPI frame layout (mode 0, 8 bit words, full duplex, one CS assertion):
 *
 *   write: addr | 0x00 | len[15:8] | len[7:0] | 3 x dummy | data[len]
 *          (header only, without dummies, when len == 0)
 *   read:  addr | 0xa0 | len[15:8] | len[7:0] | 3 x dummy | data[len] | crc
 *
 * 0xa0 is "read" (bit 7) with "CRC enable" (bit 5). The 4th received byte
 * is a status byte, bit 7 or bit 5 set means the transfer was refused. The
 * read CRC is CRC-16 with the reflected 0x8408 polynomial, initial value
 * 0xffff and no final xor (crc_ccitt()), transmitted little endian.
 */

#include <linux/bits.h>
#include <linux/crc-ccitt.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/input.h>
#include <linux/input/mt.h>
#include <linux/input/touchscreen.h>
#include <linux/interrupt.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/pm.h>
#include <linux/regulator/consumer.h>
#include <linux/slab.h>
#include <linux/spi/spi.h>

#define FTS_SPI_CMD_WRITE		0x00
#define FTS_SPI_CMD_READ		BIT(7)
#define FTS_SPI_CMD_CRC_EN		BIT(5)
#define FTS_SPI_STATUS_ERR		(BIT(7) | BIT(5))
#define FTS_SPI_HDR_LEN			4
#define FTS_SPI_DUMMY_LEN		3
#define FTS_SPI_DATA_OFFSET		(FTS_SPI_HDR_LEN + FTS_SPI_DUMMY_LEN)
#define FTS_SPI_CRC_LEN			2
#define FTS_SPI_RETRIES			3
#define FTS_SPI_BUF_LEN			256
#define FTS_SPI_MAX_DATA_LEN		(FTS_SPI_BUF_LEN - FTS_SPI_DATA_OFFSET - \
					 FTS_SPI_CRC_LEN)

/* Registers of the running (application) firmware */
#define FTS_REG_TOUCH_DATA		0x01
#define FTS_REG_CHIP_ID2		0x9f
#define FTS_REG_CHIP_ID			0xa3
#define FTS_REG_POWER_MODE		0xa5
#define FTS_POWER_MODE_SLEEP		0x03
#define FTS_REG_FW_VER			0xa6
#define FTS_REG_VENDOR_ID		0xa8

/* ROM bootloader commands, only used for diagnostics */
#define FTS_CMD_START1			0x55
#define FTS_CMD_START_DELAY_MS		12
#define FTS_CMD_READ_ID			0x90

#define FT3658S_CHIP_ID_H		0x36
#define FT3658S_CHIP_ID_L		0x58
#define FT3658S_BOOT_ID_L		0xa8

#define FTS_MAX_TOUCHES			10
#define FTS_POINT_LEN			6
#define FTS_TOUCH_HDR_LEN		2
#define FTS_TOUCH_DATA_LEN		(FTS_TOUCH_HDR_LEN + \
					 FTS_MAX_TOUCHES * FTS_POINT_LEN)
#define FTS_COORD_MAX			0xfff

/* Event types, upper nibble of the second byte of the touch report */
#define FTS_ETYPE_TOUCH			0x0
#define FTS_ETYPE_EVENT_NUM		0x2

/* Per point event flag, bits 7:6 of the first byte of a point */
#define FTS_EVENT_DOWN			0
#define FTS_EVENT_UP			1
#define FTS_EVENT_CONTACT		2

/* Vendor driver replaces 0 pressure / area by these values */
#define FTS_DEFAULT_PRESSURE		0x3f
#define FTS_DEFAULT_AREA		0x09

/* TODO(device): vendor values, verify the minimums on the device */
#define FTS_RESET_ASSERT_US		1000
#define FTS_POWER_ON_DELAY_US		2000
#define FTS_RESET_DELAY_MS		200
#define FTS_READY_POLL_MS		200
#define FTS_READY_TIMEOUT_MS		1000

struct ft3658s_ts {
	struct spi_device *spi;
	struct input_dev *input;
	struct gpio_desc *reset_gpio;
	struct regulator_bulk_data supplies[2];
	struct touchscreen_properties prop;
	bool powered;
	/* Serialises use of tx_buf / rx_buf */
	struct mutex bus_lock;
	u8 *tx_buf;
	u8 *rx_buf;
	u8 touch_buf[FTS_TOUCH_DATA_LEN];
};

static int ft3658s_xfer(struct ft3658s_ts *ts, size_t len)
{
	struct spi_transfer xfer = {
		.tx_buf = ts->tx_buf,
		.rx_buf = ts->rx_buf,
		.len = len,
	};
	int error;

	error = spi_sync_transfer(ts->spi, &xfer, 1);
	if (error)
		return error;

	if (ts->rx_buf[FTS_SPI_HDR_LEN - 1] & FTS_SPI_STATUS_ERR)
		return -EIO;

	return 0;
}

static int ft3658s_write(struct ft3658s_ts *ts, u8 addr,
			 const u8 *data, size_t len)
{
	size_t xfer_len = FTS_SPI_HDR_LEN;
	int error = -EIO;
	u8 status;
	int retry;

	if (len > FTS_SPI_MAX_DATA_LEN)
		return -EINVAL;

	mutex_lock(&ts->bus_lock);

	memset(ts->tx_buf, 0, FTS_SPI_DATA_OFFSET + len);
	ts->tx_buf[0] = addr;
	ts->tx_buf[1] = FTS_SPI_CMD_WRITE;
	ts->tx_buf[2] = len >> 8;
	ts->tx_buf[3] = len & 0xff;
	if (len) {
		memcpy(&ts->tx_buf[FTS_SPI_DATA_OFFSET], data, len);
		xfer_len = FTS_SPI_DATA_OFFSET + len;
	}

	for (retry = 0; retry < FTS_SPI_RETRIES; retry++) {
		error = ft3658s_xfer(ts, xfer_len);
		if (!error)
			break;
	}
	status = ts->rx_buf[FTS_SPI_HDR_LEN - 1];

	mutex_unlock(&ts->bus_lock);

	if (error)
		dev_dbg(&ts->spi->dev, "write 0x%02x failed: %d (status 0x%02x)\n",
			addr, error, status);

	return error;
}

static int ft3658s_write_reg(struct ft3658s_ts *ts, u8 reg, u8 val)
{
	return ft3658s_write(ts, reg, &val, 1);
}

static int ft3658s_read(struct ft3658s_ts *ts, u8 addr, u8 *data, size_t len)
{
	size_t xfer_len = FTS_SPI_DATA_OFFSET + len + FTS_SPI_CRC_LEN;
	const u8 *payload = &ts->rx_buf[FTS_SPI_DATA_OFFSET];
	u16 crc_calc, crc_read;
	int error = -EIO;
	int retry;

	if (!len || len > FTS_SPI_MAX_DATA_LEN)
		return -EINVAL;

	mutex_lock(&ts->bus_lock);

	memset(ts->tx_buf, 0, xfer_len);
	ts->tx_buf[0] = addr;
	ts->tx_buf[1] = FTS_SPI_CMD_READ | FTS_SPI_CMD_CRC_EN;
	ts->tx_buf[2] = len >> 8;
	ts->tx_buf[3] = len & 0xff;

	for (retry = 0; retry < FTS_SPI_RETRIES; retry++) {
		error = ft3658s_xfer(ts, xfer_len);
		if (error)
			continue;

		crc_calc = crc_ccitt(0xffff, payload, len);
		crc_read = payload[len] | (payload[len + 1] << 8);
		if (crc_calc != crc_read) {
			error = -EBADMSG;
			continue;
		}

		memcpy(data, payload, len);
		break;
	}

	mutex_unlock(&ts->bus_lock);

	if (error)
		dev_dbg(&ts->spi->dev, "read 0x%02x failed: %d\n", addr, error);

	return error;
}

static int ft3658s_read_reg(struct ft3658s_ts *ts, u8 reg, u8 *val)
{
	return ft3658s_read(ts, reg, val, 1);
}

static int ft3658s_power_on(struct ft3658s_ts *ts)
{
	int error;
	int i;

	gpiod_set_value_cansleep(ts->reset_gpio, 1);
	usleep_range(FTS_RESET_ASSERT_US, FTS_RESET_ASSERT_US + 1000);

	/* Vendor order: vdd (analog, 3.0V) first, then iovdd (1.8V) */
	for (i = 0; i < ARRAY_SIZE(ts->supplies); i++) {
		error = regulator_enable(ts->supplies[i].consumer);
		if (error) {
			dev_err(&ts->spi->dev, "failed to enable %s: %d\n",
				ts->supplies[i].supply, error);
			while (--i >= 0)
				regulator_disable(ts->supplies[i].consumer);
			return error;
		}
	}

	/* TODO(device): vendor has no explicit delay here */
	usleep_range(FTS_POWER_ON_DELAY_US, FTS_POWER_ON_DELAY_US + 1000);

	gpiod_set_value_cansleep(ts->reset_gpio, 0);
	msleep(FTS_RESET_DELAY_MS);
	ts->powered = true;

	return 0;
}

static void ft3658s_power_off(struct ft3658s_ts *ts)
{
	if (!ts->powered)
		return;

	gpiod_set_value_cansleep(ts->reset_gpio, 1);
	usleep_range(FTS_RESET_ASSERT_US, FTS_RESET_ASSERT_US + 1000);

	/* Vendor order: vdd first, then iovdd */
	regulator_disable(ts->supplies[0].consumer);
	regulator_disable(ts->supplies[1].consumer);
	ts->powered = false;
}

static void ft3658s_power_off_action(void *data)
{
	ft3658s_power_off(data);
}

/*
 * When the application firmware does not answer, ask the ROM bootloader for
 * its ID. This tells "no/invalid firmware in flash" apart from "no SPI
 * communication at all".
 */
static void ft3658s_check_bootloader(struct ft3658s_ts *ts)
{
	struct device *dev = &ts->spi->dev;
	u8 id[2];
	int error;

	/*
	 * Upgrade spec 1.0 parts (FT3658S) take a bare 0x55 header, older
	 * parts expect 0x55 0xaa.
	 */
	error = ft3658s_write(ts, FTS_CMD_START1, NULL, 0);
	if (error) {
		dev_err(dev, "no answer on SPI: %d\n", error);
		return;
	}

	msleep(FTS_CMD_START_DELAY_MS);

	error = ft3658s_read(ts, FTS_CMD_READ_ID, id, sizeof(id));
	if (error) {
		dev_err(dev, "failed to read boot ID: %d\n", error);
		return;
	}

	if (id[0] == FT3658S_CHIP_ID_H && id[1] == FT3658S_BOOT_ID_L)
		dev_err(dev, "controller is stuck in its bootloader, flash firmware is missing or corrupt\n");
	else
		dev_err(dev, "unexpected boot ID 0x%02x%02x\n", id[0], id[1]);
}

static int ft3658s_wait_ready(struct ft3658s_ts *ts)
{
	unsigned int elapsed = 0;
	u8 id_h = 0, id_l = 0;
	int error;

	do {
		error = ft3658s_read_reg(ts, FTS_REG_CHIP_ID, &id_h);
		if (!error)
			error = ft3658s_read_reg(ts, FTS_REG_CHIP_ID2, &id_l);
		if (!error && id_h == FT3658S_CHIP_ID_H &&
		    id_l == FT3658S_CHIP_ID_L)
			return 0;

		msleep(FTS_READY_POLL_MS);
		elapsed += FTS_READY_POLL_MS;
	} while (elapsed < FTS_READY_TIMEOUT_MS);

	dev_err(&ts->spi->dev, "chip ID mismatch: 0x%02x%02x (err %d)\n",
		id_h, id_l, error);

	return -ENODEV;
}

static int ft3658s_identify(struct ft3658s_ts *ts)
{
	struct device *dev = &ts->spi->dev;
	u8 fw_ver = 0, vendor = 0;
	int error;

	error = ft3658s_wait_ready(ts);
	if (error) {
		ft3658s_check_bootloader(ts);
		/* Leave the bootloader again */
		gpiod_set_value_cansleep(ts->reset_gpio, 1);
		usleep_range(FTS_RESET_ASSERT_US, FTS_RESET_ASSERT_US + 1000);
		gpiod_set_value_cansleep(ts->reset_gpio, 0);
		return error;
	}

	ft3658s_read_reg(ts, FTS_REG_FW_VER, &fw_ver);
	ft3658s_read_reg(ts, FTS_REG_VENDOR_ID, &vendor);

	dev_info(dev, "FT3658S, firmware 0x%02x, vendor ID 0x%02x\n",
		 fw_ver, vendor);

	return 0;
}

static void ft3658s_report_points(struct ft3658s_ts *ts, unsigned int count)
{
	struct input_dev *input = ts->input;
	unsigned int i, id, event, x, y;
	const u8 *p;

	for (i = 0; i < count; i++) {
		p = &ts->touch_buf[FTS_TOUCH_HDR_LEN + i * FTS_POINT_LEN];

		id = p[2] >> 4;
		/* Unused entries read back as 0xff */
		if (id >= FTS_MAX_TOUCHES)
			break;

		event = p[0] >> 6;
		if (event != FTS_EVENT_DOWN && event != FTS_EVENT_CONTACT)
			continue;

		x = ((p[0] & 0x0f) << 8) | p[1];
		y = ((p[2] & 0x0f) << 8) | p[3];

		input_mt_slot(input, id);
		input_mt_report_slot_state(input, MT_TOOL_FINGER, true);
		touchscreen_report_pos(input, &ts->prop, x, y, true);
		input_report_abs(input, ABS_MT_TOUCH_MAJOR,
				 p[5] ?: FTS_DEFAULT_AREA);
		input_report_abs(input, ABS_MT_PRESSURE,
				 p[4] ?: FTS_DEFAULT_PRESSURE);
	}

	/* Contacts that were not reported in this frame are released */
	input_mt_sync_frame(input);
	input_sync(input);
}

static irqreturn_t ft3658s_irq(int irq, void *dev_id)
{
	struct ft3658s_ts *ts = dev_id;
	struct device *dev = &ts->spi->dev;
	u8 *buf = ts->touch_buf;
	unsigned int etype, count;
	int error;

	error = ft3658s_read(ts, FTS_REG_TOUCH_DATA, buf, FTS_TOUCH_DATA_LEN);
	if (error) {
		dev_err_ratelimited(dev, "failed to read touch data: %d\n",
				    error);
		return IRQ_HANDLED;
	}

	if (buf[1] == 0xff && buf[2] == 0xff && buf[3] == 0xff &&
	    buf[4] == 0xff) {
		/*
		 * Firmware (re)initialised itself, e.g. after an internal
		 * watchdog reset. Release all contacts.
		 * TODO(device): vendor also restores glove/charger/edge modes.
		 */
		dev_dbg(dev, "firmware reinitialised\n");
		input_mt_sync_frame(ts->input);
		input_sync(ts->input);
		return IRQ_HANDLED;
	}

	etype = buf[1] >> 4;
	count = buf[1] & 0x0f;

	switch (etype) {
	case FTS_ETYPE_TOUCH:
		if (count > FTS_MAX_TOUCHES)
			break;
		ft3658s_report_points(ts, FTS_MAX_TOUCHES);
		break;

	case FTS_ETYPE_EVENT_NUM:
		if (!count || count > FTS_MAX_TOUCHES)
			break;
		ft3658s_report_points(ts, count);
		break;

	default:
		/* Pen (0x0b), gesture (0x80) etc. are not enabled on nicole */
		dev_dbg(dev, "unhandled event type 0x%x\n", etype);
		break;
	}

	return IRQ_HANDLED;
}

static int ft3658s_input_init(struct ft3658s_ts *ts)
{
	struct device *dev = &ts->spi->dev;
	struct input_dev *input;
	int error;

	input = devm_input_allocate_device(dev);
	if (!input)
		return -ENOMEM;

	ts->input = input;
	input->name = "FocalTech FT3658S Touchscreen";
	input->phys = "input/ts";
	input->id.bustype = BUS_SPI;

	input_set_abs_params(input, ABS_MT_POSITION_X, 0, FTS_COORD_MAX, 0, 0);
	input_set_abs_params(input, ABS_MT_POSITION_Y, 0, FTS_COORD_MAX, 0, 0);
	input_set_abs_params(input, ABS_MT_TOUCH_MAJOR, 0, 0xff, 0, 0);
	input_set_abs_params(input, ABS_MT_PRESSURE, 0, 0xff, 0, 0);

	/* nicole: touchscreen-size-x/y = 1080/2400, inverted x and y */
	touchscreen_parse_properties(input, true, &ts->prop);

	error = input_mt_init_slots(input, FTS_MAX_TOUCHES,
				    INPUT_MT_DIRECT | INPUT_MT_DROP_UNUSED);
	if (error)
		return error;

	return input_register_device(input);
}

static int ft3658s_probe(struct spi_device *spi)
{
	struct device *dev = &spi->dev;
	struct ft3658s_ts *ts;
	int error;

	if (spi->irq <= 0)
		return dev_err_probe(dev, -EINVAL, "no IRQ specified\n");

	spi->mode = SPI_MODE_0;
	spi->bits_per_word = 8;
	error = spi_setup(spi);
	if (error)
		return error;

	ts = devm_kzalloc(dev, sizeof(*ts), GFP_KERNEL);
	if (!ts)
		return -ENOMEM;

	ts->spi = spi;
	spi_set_drvdata(spi, ts);

	error = devm_mutex_init(dev, &ts->bus_lock);
	if (error)
		return error;

	/* Separate allocations so that both buffers are DMA safe */
	ts->tx_buf = devm_kzalloc(dev, FTS_SPI_BUF_LEN, GFP_KERNEL);
	ts->rx_buf = devm_kzalloc(dev, FTS_SPI_BUF_LEN, GFP_KERNEL);
	if (!ts->tx_buf || !ts->rx_buf)
		return -ENOMEM;

	ts->supplies[0].supply = "vdd";
	ts->supplies[1].supply = "iovdd";
	error = devm_regulator_bulk_get(dev, ARRAY_SIZE(ts->supplies),
					ts->supplies);
	if (error)
		return dev_err_probe(dev, error, "failed to get regulators\n");

	ts->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(ts->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ts->reset_gpio),
				     "failed to get reset GPIO\n");

	error = ft3658s_power_on(ts);
	if (error)
		return error;

	error = devm_add_action_or_reset(dev, ft3658s_power_off_action, ts);
	if (error)
		return error;

	error = ft3658s_identify(ts);
	if (error)
		return error;

	error = ft3658s_input_init(ts);
	if (error)
		return dev_err_probe(dev, error, "failed to set up input\n");

	/*
	 * Trigger type comes from DT. The vendor driver forces
	 * IRQF_TRIGGER_FALLING. TODO(device): confirm edge vs. level.
	 */
	error = devm_request_threaded_irq(dev, spi->irq, NULL, ft3658s_irq,
					  IRQF_ONESHOT, dev_name(dev), ts);
	if (error)
		return dev_err_probe(dev, error, "failed to request IRQ\n");

	/*
	 * TODO(device): the vendor driver polls 0xa3 (chip ID) and 0x91 (flow
	 * work counter) every second and hard resets the controller when the
	 * counter is stuck (ESD recovery). Add it if lockups are observed.
	 */

	return 0;
}

static int ft3658s_suspend(struct device *dev)
{
	struct ft3658s_ts *ts = dev_get_drvdata(dev);

	disable_irq(ts->spi->irq);

	/* Best effort, power is removed right after */
	ft3658s_write_reg(ts, FTS_REG_POWER_MODE, FTS_POWER_MODE_SLEEP);

	ft3658s_power_off(ts);

	return 0;
}

static int ft3658s_resume(struct device *dev)
{
	struct ft3658s_ts *ts = dev_get_drvdata(dev);
	int error;

	error = ft3658s_power_on(ts);
	if (error)
		return error;

	error = ft3658s_wait_ready(ts);
	if (error)
		dev_warn(dev, "controller not ready after resume\n");

	enable_irq(ts->spi->irq);

	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(ft3658s_pm_ops, ft3658s_suspend,
				ft3658s_resume);

static const struct spi_device_id ft3658s_spi_ids[] = {
	{ "ft3658s" },
	{ }
};
MODULE_DEVICE_TABLE(spi, ft3658s_spi_ids);

static const struct of_device_id ft3658s_of_match[] = {
	{ .compatible = "focaltech,ft3658s" },
	{ }
};
MODULE_DEVICE_TABLE(of, ft3658s_of_match);

static struct spi_driver ft3658s_driver = {
	.driver = {
		.name = "focaltech-ft3658s",
		.of_match_table = ft3658s_of_match,
		.pm = pm_sleep_ptr(&ft3658s_pm_ops),
	},
	.probe = ft3658s_probe,
	.id_table = ft3658s_spi_ids,
};
module_spi_driver(ft3658s_driver);

MODULE_DESCRIPTION("FocalTech FT3658S SPI touchscreen driver");
MODULE_LICENSE("GPL");
