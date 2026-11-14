import sys, struct, libfdt
def entries(p):
    b=open(p,'rb').read()
    magic,total,hsz,esz,cnt,off,page,ver=struct.unpack('>8I',b[:32])
    print(p, 'total',total,'hdr',hsz,'esz',esz,'cnt',cnt,'off',off,'page',page,'ver',ver)
    for i in range(cnt):
        e=struct.unpack('>8I',b[off+i*esz:off+(i+1)*esz])
        print('  entry',i,'size',e[0],'off',e[1],'id',hex(e[2]),'rev',hex(e[3]),'custom',[hex(x) for x in e[4:]])
        d=b[e[1]:e[1]+e[0]]
        f=libfdt.Fdt(d)
        print('  fdt version',f.version(),'last_comp',f.last_comp_version(),'totalsize',f.totalsize(),'boot_cpuid',f.boot_cpuid_phys(),'rsvmap',f.num_mem_rsv())
        def walk(n,path,dep):
            o=f.first_property_offset(n,[libfdt.FDT_ERR_NOTFOUND])
            while o>=0:
                pr=f.get_property_by_offset(o)
                print('   '+'  '*dep+path, pr.name, bytes(pr)[:40].hex() if len(pr)<64 else len(pr))
                o=f.next_property_offset(o,[libfdt.FDT_ERR_NOTFOUND])
            c=f.first_subnode(n,[libfdt.FDT_ERR_NOTFOUND])
            while c>=0:
                print('   '+'  '*dep+'node', f.get_name(c)); walk(c,path+f.get_name(c)+'/',dep+1)
                c=f.next_subnode(c,[libfdt.FDT_ERR_NOTFOUND])
        walk(0,'/',0)
for p in sys.argv[1:]: entries(p)
