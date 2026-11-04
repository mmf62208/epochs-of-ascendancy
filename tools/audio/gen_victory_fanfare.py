# Original brass-ish fanfare (Ink, 2026-11-04). Additive synthesis, project-owned.
import numpy as np, wave
SR=44100
def note(f,dur,amp=1.0,vib=True):
    t=np.arange(int(SR*dur))/SR
    v=1+ (0.004*np.sin(2*np.pi*5.5*t)*np.clip(t/0.3,0,1) if vib else 0)
    ph=2*np.pi*f*np.cumsum(v)/SR
    bright=np.clip(t/0.06,0,1)  # brass "blat" opens up
    s=sum((1/k**1.1)*(bright if k>3 else 1)*np.sin(k*ph) for k in range(1,12))
    env=np.minimum(np.clip(t/0.03,0,1), np.clip((dur-t)/0.08,0,1))*(0.85+0.15*np.exp(-t*6))
    return amp*s*env
def timp(dur,f=65):
    t=np.arange(int(SR*dur))/SR
    return 0.9*np.exp(-t*3)*(np.sin(2*np.pi*f*t)+0.5*np.sin(2*np.pi*f*1.5*t))+0.3*np.random.randn(len(t))*np.exp(-t*30)
def mix(parts,total):
    out=np.zeros(int(SR*total))
    for st,sig in parts:
        i=int(SR*st); out[i:i+len(sig)]+=sig[:len(out)-i]
    return out
C4,E4,G4,C5,E5,G5,Bb4,F4,A4=261.63,329.63,392.0,523.25,659.25,783.99,466.16,349.23,440.0
P=[]
# pickup triplet + call (Bb major-ish C major motif)
seq=[(0,G4,.16),(.18,G4,.16),(.36,G4,.16),(.54,C5,.7),(1.3,G4,.3),(1.62,C5,.3),(1.94,E5,1.0)]
for st,f,d in seq: P.append((st,note(f,d,1.0)))
# harmony horns under long notes
for st,fs,d in [(.54,[E4,G4],.7),(1.94,[C4,G4,C5],1.0),(3.0,[F4,A4,C5],.6),(3.62,[G4,B:=493.88,D5:=587.33],.6),(4.25,[C4,E4,G4,C5,E5],1.9)]:
    for f in fs: P.append((st,note(f,d,0.55)))
P.append((3.0,note(F4*2*0.999,.6,0.8)));P.append((3.62,note(G5*0.75*1.333,.6,0.0)))
P.append((4.25,note(G5,1.9,0.9)))
for st in [0.54,1.94,4.25,4.6,4.95]: P.append((st,timp(1.4)))
y=mix(P,6.6)
# simple hall reverb
for d,g in [(0.031,0.35),(0.053,0.28),(0.089,0.2),(0.137,0.14),(0.21,0.09)]:
    k=int(SR*d); y[k:]+=g*y[:-k]
y/=np.max(np.abs(y))*1.05
w=wave.open('/tmp/victory_fanfare.wav','wb');w.setnchannels(1);w.setsampwidth(2);w.setframerate(SR);w.writeframes((y*32767).astype(np.int16).tobytes());w.close()
