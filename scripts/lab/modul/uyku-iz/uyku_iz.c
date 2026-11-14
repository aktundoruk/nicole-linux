// SPDX-License-Identifier: GPL-2.0
/*
 * uyku_iz: what is still on at the moment of s2idle (2 Kasım 2026, kernel r14).
 *
 * qcom_stats says aosd/cxsd/ddr never move, even with ADSP and SLPI asleep, and debugfs cannot
 * be read from outside while the phone sleeps. So this module takes a snapshot from inside: a
 * kretprobe on dpm_suspend_noirq (s2idle_loop is inlined) wakes a non-freezable kthread, which
 * reads the summaries into buffers just before the CPUs go idle. It also logs which way the PCIe suspend path went.
 * Nothing here writes to hardware, except that d3=1 lets the empty root port go to D3hot, so
 * dw_pcie_suspend_noirq takes the power-off path instead of leaving every PCIe clock on, and
 * oto=1 moves the switching rails our DTS forces to PWM (HPM) to AUTO until rmmod, and wcn=1 holds
 * the WCN6855's WLAN enable low (TLMM 64) from host power-off to resume. wcn=1 needs BT off, or
 * BT_EN keeps the chip up anyway: systemctl stop bluetooth; modprobe -r hci_uart.
 * After resume, /sys/kernel/debug/uyku_iz/{clk,genpd,icc,regulator}. The lists are walked by hand,
 * since debugfs files have no read_iter for kernel_read and the _summary paths call pm_runtime.
 * Their heads are private, so the addresses come from /proc/kallsyms:
 *
 *   s() { awk -v a="$1" '$3==a{print "0x"$1}' /proc/kallsyms; }
 *   insmod uyku_iz.ko d3=1 kok=$(s clk_root_list) gpd=$(s gpd_list) rs=$(s regulator_class) \
 *          icc=$(s icc_providers)
 */
#include <linux/clk-provider.h>
#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/gpio/driver.h>
#include <linux/interconnect-provider.h>
#include <linux/kprobes.h>
#include <linux/kthread.h>
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/pm_domain.h>
#include <linux/regulator/consumer.h>
#include <linux/regulator/driver.h>
#include <linux/seq_buf.h>
#include <linux/vmalloc.h>
#include "clk_core.h"
#include "pcie-designware.h"
#include "internal.h"
#include "icc_internal.h"

#define BOY (512 * 1024)

static unsigned long kok;
module_param(kok, ulong, 0444);
MODULE_PARM_DESC(kok, "address of clk_root_list, from /proc/kallsyms");

static unsigned long gpd, rs, icc;
module_param(gpd, ulong, 0444);
MODULE_PARM_DESC(gpd, "address of gpd_list");
module_param(rs, ulong, 0444);
MODULE_PARM_DESC(rs, "address of regulator_class");
module_param(icc, ulong, 0444);
MODULE_PARM_DESC(icc, "address of icc_providers");

static bool d3;
module_param(d3, bool, 0444);
MODULE_PARM_DESC(d3, "allow D3 on the root port when nothing is below it");

static bool oto;
module_param(oto, bool, 0444);
MODULE_PARM_DESC(oto, "switching rails in AUTO instead of the DTS's forced PWM");

static bool wcn;
module_param(wcn, bool, 0444);
MODULE_PARM_DESC(wcn, "WCN6855 WLAN enable low while the PCIe host is off");

static struct gpio_desc *wlan_en;
static bool kapandi, dusuk;

static const char * const raylar[] = { "pm8350_s10", "pm8350_s11", "pm8350_s12", "pm8350c_s1" };
static struct regulator *ray[ARRAY_SIZE(raylar)];

/* set_mode through the driver: the DTS gives these rails no REGULATOR_CHANGE_MODE */
static void ray_kipi(unsigned int mod)
{
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(ray); i++) {
		struct regulator_dev *rd;

		if (IS_ERR_OR_NULL(ray[i]))
			continue;
		rd = ray[i]->rdev;
		ret = rd->desc->ops->set_mode(rd, mod);
		pr_info("uyku_iz: %s kip=%u sonuc=%d simdi=%u\n", raylar[i], mod, ret,
			rd->desc->ops->get_mode(rd));
	}
}

static struct debugfs_blob_wrapper bloblar[4];
static struct pci_dev *kokport;
static struct dentry *dizin;
static struct task_struct *isci;
static atomic_t tetik = ATOMIC_INIT(0);

static void clk_yaz(struct seq_buf *s, struct clk_core *c, int d)
{
	struct clk_core *k;

	if (c->enable_count || c->prepare_count)
		seq_buf_printf(s, "%*s%s en=%u pre=%u hiz=%lu\n", d, "", c->name,
			       c->enable_count, c->prepare_count, c->rate);
	hlist_for_each_entry(k, &c->children, child_node)
		clk_yaz(s, k, d + 1);
}

/* clk_summary would call pm_runtime on the providers, which fails this late: walk it by hand */
static void clk_foto(void)
{
	struct hlist_head *kl = (struct hlist_head *)kok;
	struct seq_buf s;
	struct clk_core *c;

	seq_buf_init(&s, bloblar[3].data, BOY);
	if (kl)
		hlist_for_each_entry(c, kl, child_node)
			clk_yaz(&s, c, 0);
	bloblar[3].size = seq_buf_used(&s);
}

/* every domain, and who holds a performance vote on it: this is what a CX or MX vote looks like */
static void genpd_foto(void)
{
	struct list_head *l = (struct list_head *)gpd;
	struct generic_pm_domain *g;
	struct pm_domain_data *d;
	struct seq_buf s;

	seq_buf_init(&s, bloblar[0].data, BOY);
	if (l)
		list_for_each_entry(g, l, gpd_list_node) {
			seq_buf_printf(&s, "%s %s perf=%u\n", g->name,
				       g->status == GENPD_STATE_ON ? "ACIK" : "kapali",
				       g->performance_state);
			list_for_each_entry(d, &g->dev_list, list_node)
				if (g->status == GENPD_STATE_ON || to_gpd_data(d)->performance_state)
					seq_buf_printf(&s, "  %s perf=%u rpm=%d\n", dev_name(d->dev),
						       to_gpd_data(d)->performance_state,
						       d->dev->power.runtime_status);
		}
	bloblar[0].size = seq_buf_used(&s);
}

static void icc_foto(void)
{
	struct list_head *l = (struct list_head *)icc;
	struct icc_provider *p;
	struct icc_node *n;
	struct icc_req *r;
	struct seq_buf s;

	seq_buf_init(&s, bloblar[1].data, BOY);
	if (l)
		list_for_each_entry(p, l, provider_list)
			list_for_each_entry(n, &p->nodes, node_list) {
				if (!n->avg_bw && !n->peak_bw)
					continue;
				seq_buf_printf(&s, "%s ort=%u tepe=%u\n", n->name, n->avg_bw, n->peak_bw);
				hlist_for_each_entry(r, &n->req_list, req_node)
					if (r->avg_bw || r->peak_bw)
						seq_buf_printf(&s, "  %s ort=%u tepe=%u etiket=%u\n",
							       r->dev ? dev_name(r->dev) : "?",
							       r->avg_bw, r->peak_bw, r->tag);
			}
	bloblar[1].size = seq_buf_used(&s);
}

static int reg_yaz(struct device *dev, void *v)
{
	struct regulator_dev *rd = dev_to_rdev(dev);
	const char *ad = rdev_get_name(rd);
	int en = 99;

	/* rpmh answers from its cache; others may need a bus that is asleep by now */
	if (!strncmp(ad, "pm8350", 6) && rd->desc->ops->is_enabled)
		en = rd->desc->ops->is_enabled(rd);
	seq_buf_printf(v, "%s use=%u open=%d en=%d\n", ad, rd->use_count, rd->open_count, en);
	return 0;
}

static void reg_foto(void)
{
	struct seq_buf s;

	seq_buf_init(&s, bloblar[2].data, BOY);
	if (rs)
		class_for_each_device((const struct class *)rs, NULL, &s, reg_yaz);
	bloblar[2].size = seq_buf_used(&s);
}

static int isci_fn(void *v)
{
	while (!kthread_should_stop()) {
		set_current_state(TASK_INTERRUPTIBLE);
		if (!atomic_xchg(&tetik, 0)) {
			schedule();
			continue;
		}
		__set_current_state(TASK_RUNNING);
		clk_foto();
		genpd_foto();
		icc_foto();
		reg_foto();
		pr_info("uyku_iz: foto alindi\n");
	}
	return 0;
}

static int noirq_ret(struct kretprobe_instance *ri, struct pt_regs *r)
{
	atomic_set(&tetik, 1);
	wake_up_process(isci);
	return 0;
}

/* kthreads resolve paths in the initramfs root: the files are opened at insmod, in our namespace */
static int noirq_pre(struct kprobe *p, struct pt_regs *r)
{
	if (d3 && kokport && kokport->subordinate && list_empty(&kokport->subordinate->devices)) {
		kokport->bridge_d3 = 1;
		pr_info("uyku_iz: kok port bos, bridge_d3=1\n");
	}
	return 0;
}

static int d3_pre(struct kprobe *p, struct pt_regs *r)
{
	struct pci_dev *d = (struct pci_dev *)regs_get_kernel_argument(r, 0);

	pr_info("uyku_iz: d3cold? %s durum=D%d surucu=%d etkin=%d uyandirir=%d bridge_d3=%d hotplug=%d pciehp=%d\n",
		pci_name(d), d->current_state, !!d->dev.driver, pci_is_enabled(d),
		device_may_wakeup(&d->dev), d->bridge_d3, d->is_hotplug_bridge, d->is_pciehp);
	return 0;
}

static int iz_pre(struct kprobe *p, struct pt_regs *r)
{
	pr_info("uyku_iz: %s\n", p->symbol_name);
	return 0;
}

static int deinit_pre(struct kprobe *p, struct pt_regs *r)
{
	kapandi = true;
	return iz_pre(p, r);
}

static int resume_pre(struct kprobe *p, struct pt_regs *r)
{
	struct dw_pcie *pci = (struct dw_pcie *)regs_get_kernel_argument(r, 0);

	kapandi = false;
	if (dusuk) {
		/* same wait pwrseq-qcom-wcn gives the chip after enable */
		gpiod_set_raw_value(wlan_en, 1);
		dusuk = false;
		mdelay(100);
		pr_info("uyku_iz: WLAN_EN yuksek\n");
	}
	pr_info("uyku_iz: %s suspended=%d\n", p->symbol_name, pci->suspended);
	return 0;
}

static int sus_ret(struct kretprobe_instance *ri, struct pt_regs *r)
{
	if (wlan_en && kapandi) {
		gpiod_set_raw_value(wlan_en, 0);
		dusuk = true;
		pr_info("uyku_iz: WLAN_EN dusuk\n");
	}
	pr_info("uyku_iz: dw_pcie_suspend_noirq -> %ld\n", (long)regs_return_value(r));
	return 0;
}

static struct kprobe kp[] = {
	{ .symbol_name = "dpm_suspend_noirq", .pre_handler = noirq_pre },
	{ .symbol_name = "__pci_host_common_d3cold_possible", .pre_handler = d3_pre },
	{ .symbol_name = "dw_pcie_resume_noirq", .pre_handler = resume_pre },
	{ .symbol_name = "qcom_pcie_host_pme_turn_off", .pre_handler = iz_pre },
	{ .symbol_name = "qcom_pcie_host_deinit", .pre_handler = deinit_pre },
	{ .symbol_name = "qcom_pcie_deinit_2_7_0", .pre_handler = iz_pre },
	{ .symbol_name = "qcom_pcie_reset_root_port", .pre_handler = iz_pre },
	{ .symbol_name = "pci_host_handle_link_down", .pre_handler = iz_pre },
};
static struct kretprobe krp[] = {
	{ .kp.symbol_name = "dw_pcie_suspend_noirq", .handler = sus_ret, .maxactive = 2 },
	{ .kp.symbol_name = "dpm_suspend_noirq", .handler = noirq_ret, .maxactive = 2 },
};

static int __init iz_init(void)
{
	static const char * const adlar[] = { "genpd", "icc", "regulator", "clk" };
	int i, n = 0, ret;

	dizin = debugfs_create_dir("uyku_iz", NULL);
	for (i = 0; i < 4; i++) {
		bloblar[i].data = vzalloc(BOY);
		if (!bloblar[i].data) {
			ret = -ENOMEM;
			goto err;
		}
		debugfs_create_blob(adlar[i], 0400, dizin, &bloblar[i]);
	}
	kokport = pci_get_domain_bus_and_slot(0, 0, 0);
	if (oto) {
		for (i = 0; i < ARRAY_SIZE(ray); i++)
			ray[i] = regulator_get(NULL, raylar[i]);
		for (i = 0; i < ARRAY_SIZE(ray); i++)
			if (IS_ERR(ray[i]))
				pr_warn("uyku_iz: %s alinamadi: %ld\n", raylar[i], PTR_ERR(ray[i]));
		ray_kipi(REGULATOR_MODE_NORMAL);
	}
	if (wcn) {
		struct gpio_device *g = gpio_device_find_by_label("f100000.pinctrl");

		if (g) {
			wlan_en = gpio_device_get_desc(g, 64);
			gpio_device_put(g);
		}
		if (IS_ERR_OR_NULL(wlan_en)) {
			pr_warn("uyku_iz: TLMM 64 bulunamadi\n");
			wlan_en = NULL;
		}
	}
	isci = kthread_run(isci_fn, NULL, "uyku_iz");
	if (IS_ERR(isci)) {
		ret = PTR_ERR(isci);
		goto err;
	}
	for (i = 0; i < ARRAY_SIZE(kp); i++) {
		ret = register_kprobe(&kp[i]);
		if (ret)
			pr_warn("uyku_iz: %s kprobe: %d\n", kp[i].symbol_name, ret);
		else
			n++;
	}
	for (i = 0; i < ARRAY_SIZE(krp); i++) {
		ret = register_kretprobe(&krp[i]);
		if (ret)
			pr_warn("uyku_iz: %s kretprobe: %d\n", krp[i].kp.symbol_name, ret);
	}
	pr_info("uyku_iz: %d kprobe takili, kok=%lx\n", n, kok);
	return 0;
err:
	debugfs_remove_recursive(dizin);
	for (i = 0; i < 4; i++)
		vfree(bloblar[i].data);
	return ret;
}

static void __exit iz_exit(void)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(kp); i++)
		if (kp[i].addr)
			unregister_kprobe(&kp[i]);
	for (i = 0; i < ARRAY_SIZE(krp); i++)
		if (krp[i].kp.addr)
			unregister_kretprobe(&krp[i]);
	kthread_stop(isci);
	if (oto) {
		ray_kipi(REGULATOR_MODE_FAST);
		for (i = 0; i < ARRAY_SIZE(ray); i++)
			if (!IS_ERR_OR_NULL(ray[i]))
				regulator_put(ray[i]);
	}
	pci_dev_put(kokport);
	debugfs_remove_recursive(dizin);
	for (i = 0; i < 4; i++)
		vfree(bloblar[i].data);
}

module_init(iz_init);
module_exit(iz_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Snapshot of what is on at the moment of s2idle");
