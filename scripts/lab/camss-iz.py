# Adds "camss-iz" trace lines (pr_info + mdelay) to the stream-start path. Debug only.
import re, sys
D = "/mnt/lima-razer-build/src/linux-v7.3-rc6/drivers/media/platform/qcom/camss/"
IZ = 'do { pr_info("camss-iz: %s:%d\\n", __func__, __LINE__); mdelay(150); } while (0);'
def ekle(dosya, fonks, son=True):
    p = D + dosya; s = open(p).read()
    if "linux/delay.h" not in s:
        s = s.replace("#include <linux/", "#include <linux/delay.h>\n#include <linux/", 1)
    for f in fonks:
        m = re.search(r"\n[^\n;]*\b" + f + r"\([^;{]*\)\n\{\n", s)
        if not m:
            sys.exit(f"yok: {dosya} {f}")
        bas = m.end()
        # skip declarations: insert after the first blank line that ends the decl block, else at start
        govde = s[bas:]
        k = govde.find("\n\n")
        sonraki = govde.find("\n}\n")
        at = bas + k + 1 if 0 <= k < sonraki and all(
            re.match(r"\s*(const |struct |u8|u16|u32|int |unsigned|bool |enum |void |dma_addr|long )", l) or not l.strip()
            for l in govde[:k].split("\n")) else bas
        s = s[:at] + "\t" + IZ + "\n" + s[at:]
    open(p, "w").write(s)
ekle("camss-video.c", ["video_start_streaming"])
ekle("camss-vfe.c", ["vfe_set_stream", "vfe_enable_v2", "vfe_enable_output_v2", "vfe_get_output_v2"])
ekle("camss-vfe-480.c", ["vfe_wm_start", "vfe_reg_update", "vfe_enable_irq", "vfe_global_reset"])
ekle("camss-csid.c", ["csid_set_stream"])
ekle("camss-csid-gen2.c", ["csid_configure_stream"])
ekle("camss-csiphy-3ph-1-0.c", ["csiphy_lanes_enable", "csiphy_gen2_config_lanes"])
ekle("camss-csiphy.c", ["csiphy_set_stream"])
print("tamam")
# Switches for bisecting (debug only): iz_no_wm skips enabling the RDI write master,
# iz_no_csid skips the CSID stream enable.
p = D + "camss-vfe-480.c"; s = open(p).read()
s = s.replace("static void vfe_global_reset(", "static int iz_no_wm;\nmodule_param(iz_no_wm, int, 0644);\n\nstatic void vfe_global_reset(", 1)
s = s.replace("\twritel_relaxed(1 << WM_CFG_EN | MODE_MIPI_RAW << WM_CFG_MODE,", "\tpr_info(\"camss-iz: wm %d addr 0x%x incr 0x%x\\n\", wm, readl_relaxed(vfe->base + VFE_BUS_WM_IMAGE_ADDR(wm)), readl_relaxed(vfe->base + VFE_BUS_WM_FRAME_INCR(wm)));\n\tif (iz_no_wm) { pr_info(\"camss-iz: WM açılmadı\\n\"); return; }\n\twritel_relaxed(1 << WM_CFG_EN | MODE_MIPI_RAW << WM_CFG_MODE,", 1)
open(p, "w").write(s)
p = D + "camss-csid-gen2.c"; s = open(p).read()
s = s.replace("static void csid_configure_stream(", "static int iz_no_csid;\nmodule_param(iz_no_csid, int, 0644);\n\nstatic void csid_configure_stream(", 1)
open(p, "w").write(s)
print("anahtarlar tamam")
# iz_addr: write this IOVA instead of the buffer's (debug only).
p = D + "camss-vfe-480.c"; s = open(p).read()
s = s.replace("static void vfe_wm_update(", "static uint iz_addr;\nmodule_param(iz_addr, uint, 0644);\n\nstatic void vfe_wm_update(", 1)
s = s.replace("\twritel_relaxed(addr, vfe->base + VFE_BUS_WM_IMAGE_ADDR(wm));",
              "\tpr_info(\"camss-iz: wm_update wm %d addr 0x%x -> 0x%x\\n\", wm, addr, iz_addr ? iz_addr : addr);\n\tif (iz_addr)\n\t\taddr = iz_addr;\n\twritel_relaxed(addr, vfe->base + VFE_BUS_WM_IMAGE_ADDR(wm));", 1)
open(p, "w").write(s)
print("iz_addr tamam")
# iz_camnoc_hz / iz_ekstra (debug only): applied when a VFE line starts streaming.
p = D + "camss-vfe.c"; s = open(p).read()
s = s.replace("static int vfe_set_stream(", '''static uint iz_camnoc_hz;
module_param(iz_camnoc_hz, uint, 0644);
static int iz_ekstra;
module_param(iz_ekstra, int, 0644);

static void iz_saatler(struct vfe_device *vfe)
{
	static const char * const adlar[] = { "core_ahb", "cam_sf_axi" };
	struct device *dev = vfe->camss->dev;
	struct clk *c;
	int i;

	if (iz_camnoc_hz) {
		c = clk_get(dev, "camnoc_axi_src");
		if (!IS_ERR(c)) {
			pr_info("camss-iz: camnoc_axi_src %lu -> set %u: %d -> %lu\\n", clk_get_rate(c),
				iz_camnoc_hz, clk_set_rate(c, iz_camnoc_hz), clk_get_rate(c));
			clk_put(c);
		}
	}
	for (i = 0; iz_ekstra && i < ARRAY_SIZE(adlar); i++) {
		c = clk_get(dev, adlar[i]);
		pr_info("camss-iz: %s açılıyor: %d\\n", adlar[i], IS_ERR(c) ? (int)PTR_ERR(c) : clk_prepare_enable(c));
	}
}

static int vfe_set_stream(''', 1)
k = s.index("static int vfe_set_stream(struct v4l2_subdev *sd, int enable)\n{")
m = s.index("mdelay(150); } while (0);\n", k) + len("mdelay(150); } while (0);\n")
s = s[:m] + "\tif (enable)\n\t\tiz_saatler(vfe);\n" + s[m:]
open(p, "w").write(s)
print("saat anahtarları tamam")
# iz_tbu (debug only): vote the four MMNOC TBU GDSCs on (GCC 0x17d050/58/54/6c, clear SW_COLLAPSE)
# behind gcc's back, before the stream starts.
p = D + "camss-vfe.c"; s = open(p).read()
s = s.replace("static void iz_saatler(struct vfe_device *vfe)\n{", '''static int iz_tbu;
module_param(iz_tbu, int, 0644);

static void iz_saatler(struct vfe_device *vfe)
{
	static const u32 tbu[] = { 0x17d050, 0x17d058, 0x17d054, 0x17d06c };
	int k;

	for (k = 0; iz_tbu && k < ARRAY_SIZE(tbu); k++) {
		void __iomem *r = ioremap(tbu[k], 4);
		u32 once;

		if (!r)
			continue;
		once = readl(r);
		writel(once & ~BIT(0), r);
		udelay(100);
		pr_info("camss-iz: tbu gdsc 0x%x: 0x%08x -> 0x%08x\\n", tbu[k], once, readl(r));
		iounmap(r);
	}''', 1)
open(p, "w").write(s)
print("tbu tamam")
