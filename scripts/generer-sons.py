import numpy as np, wave, sys, os
SR=44100
out=sys.argv[1]
def env(n, a=0.005, r=0.2, curve=4):
    t=np.arange(n)/SR; d=n/SR
    e=np.minimum(1, t/max(a,1e-4))
    e*=np.exp(-curve*np.maximum(0,t-a)/max(d-a,1e-4))
    fade=int(0.004*SR); e[-fade:]*=np.linspace(1,0,fade)
    return e
def tone(f, d, a=0.004, curve=5, harm=(1,0.25,0.08), detune=0.0):
    n=int(d*SR); t=np.arange(n)/SR; s=np.zeros(n)
    for i,h in enumerate(harm):
        s+=h*np.sin(2*np.pi*f*(i+1)*t*(1+detune*i))
    return s*env(n,a,curve=curve)
def bell(f,d,curve=4):
    n=int(d*SR); t=np.arange(n)/SR
    mod=np.sin(2*np.pi*f*1.4*t)*2.0*np.exp(-6*t)
    return np.sin(2*np.pi*f*t+mod)*env(n,0.002,curve=curve)
def noise_sweep(d, f0, f1, q=6):
    from scipy.signal import butter, lfilter
    n=int(d*SR); x=np.random.default_rng(1).standard_normal(n)
    y=np.zeros(n); blk=512
    for i in range(0,n,blk):
        f=f0+(f1-f0)*(i/n)
        lo=max(f/ (1+1/q),40); hi=min(f*(1+1/q),SR/2-100)
        b,a=butter(2,[lo/(SR/2),hi/(SR/2)],btype='band')
        y[i:i+blk]=lfilter(b,a,x[i:i+blk])
    return y/np.max(np.abs(y))
def mix(parts, total):
    s=np.zeros(int(total*SR))
    for off,sig in parts:
        i=int(off*SR); s[i:i+len(sig)]+=sig[:len(s)-i]
    return s
def reverb(s, amt=0.25):
    out=s.copy()
    for dl,g in [(0.029,0.5),(0.037,0.4),(0.053,0.3),(0.071,0.22),(0.097,0.15)]:
        k=int(dl*SR); out[k:]+=g*amt*s[:-k]
    return out
def save(name, s, vol=0.7):
    s=reverb(s); s=s/np.max(np.abs(s))*vol
    data=(s*32767).astype(np.int16)
    with wave.open(os.path.join(out,name+'.wav'),'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())
# clic de navigation : petit « tok » de verre
save('click', mix([(0,tone(1850,0.06,curve=9,harm=(1,0.3))),(0,tone(920,0.05,curve=10,harm=(0.6,)))],0.09), 0.35)
# départ d'analyse : souffle qui monte + accord
sw=noise_sweep(0.7,300,3200)*env(int(0.7*SR),0.35,curve=2)*0.5
save('start', mix([(0,sw),(0.35,tone(523.25,0.6,curve=3)),(0.42,tone(659.25,0.6,curve=3)),(0.49,tone(783.99,0.7,curve=3))],1.3), 0.6)
# tic de progression
save('tick', tone(2400,0.035,curve=12,harm=(1,0.2)), 0.18)
# élément trouvé : bip doux
save('found', mix([(0,bell(1318.5,0.25,curve=6)),(0.06,bell(1760,0.3,curve=6))],0.45), 0.4)
# réussite : arpège brillant
notes=[523.25,659.25,783.99,1046.5,1318.5]
save('success', mix([(i*0.085,bell(f,0.9,curve=3.5)) for i,f in enumerate(notes)]+[(0.45,tone(261.63,1.0,curve=2.5,harm=(0.6,0.2)))],1.6), 0.65)
# alerte : deux tons graves insistants
a=lambda f: tone(f,0.22,a=0.01,curve=3,harm=(1,0.5,0.3,0.15))
save('alert', mix([(0,a(880)),(0.25,a(659.25)),(0.5,a(880)),(0.75,a(659.25))],1.1), 0.7)
# booster : montée rapide
n=int(0.9*SR); t=np.arange(n)/SR; f=200+1800*(t/0.9)**2
ph=2*np.pi*np.cumsum(f)/SR
rise=(np.sin(ph)+0.3*np.sin(2*ph))*env(n,0.6,curve=1.5)*0.6
save('boost', mix([(0,rise),(0,noise_sweep(0.9,400,6000)*env(n,0.7,curve=1.5)*0.35),(0.82,bell(1567.98,0.6,curve=4))],1.5), 0.6)
# glissement d'écran
save('whoosh', noise_sweep(0.32,1800,500)*env(int(0.32*SR),0.08,curve=4), 0.22)
