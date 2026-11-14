#!/usr/bin/env python3
"""Simulation of the libcamera soft IPA AGC loop (v0.7.2 agc.cpp): stats every 4th frame,
sensor delay 2, 5-bin MSV target 2.5, dead band 0.2. Prints settle frame and tail wobble."""
import numpy as np
rng=np.random.default_rng(1)
def msv(exp,gain,scene):
    y=np.clip(scene*exp*gain+16,0,255)          # 8-bit, black 16 (=64>>2)
    h=np.bincount((y//4).astype(int),minlength=64)[:64]
    b0=16//4; hs=64-b0; per=hs//5; mod=hs//(hs%5+1)
    bins=np.zeros(5)
    for i in range(hs): bins[(i-(i//mod))//per]+=h[b0+i]
    return (bins*np.arange(1,6)).sum()/bins.sum()
def run(k,ms,scene,exp=6,gain=1.0,n=300,emin=6,emax=2079):
    hist=[];req=[(exp,gain)]*3;e,g=exp,gain
    for f in range(n):
        ae,ag=req[max(0,len(req)-3)]               # delay 2
        hist.append((ae,ag))
        if f%4==0:
            m=msv(ae,ag,scene);err=2.5-m
            if abs(err)>0.2:
                st=np.clip(err*k,-ms,ms);fa=1+st;e,g=ae,ag
                if fa>1:
                    if e<emax: e=max(int(e*fa),e+1)
                    else: g=g*fa
                else:
                    if g>1: g=max(1,g*fa)
                    else: e=min(int(e*fa),e-1)
                e=int(np.clip(e,emin,emax));g=float(np.clip(g,1,16))
        req.append((e,g))
    return hist
for parlak in (0.002,0.05,1.0):
    scene=rng.lognormal(np.log(parlak),1.0,20000)
    for k,ms in ((0.04,0.15),(0.12,0.4),(0.2,0.5),(0.3,0.5)):
        for start in ((6,1.0),(2079,16.0)):
            h=run(k,ms,scene,*start)
            v=np.array([a*b for a,b in h]); fin=v[-1]
            conv=next((i for i in range(len(v)) if np.all(np.abs(np.log(v[i:]/fin))<0.15)),None)
            tail=v[-60:]; osc=(tail.max()/tail.min())
            print(f"parlak {parlak:5} k {k:4} ms {ms:4} start {start[0]:4}: oturma karesi {conv}, son {fin:8.0f}, son60 oynama x{osc:.2f}")
