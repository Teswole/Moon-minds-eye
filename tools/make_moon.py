# 2026-11-13 2:30 PM CST — procedural near-side moon maps for Moon Mind's Eye (makes moon-albedo.png and moon-normal.png)
import numpy as np, math
from PIL import Image
from scipy.ndimage import gaussian_filter, zoom
rng=np.random.default_rng(42)
S=900; c=(S-1)/2; R=S/2-3
yy,xx=np.mgrid[0:S,0:S].astype(np.float32)
X=(xx-c)/R; Y=(c-yy)/R; R2=X*X+Y*Y; inside=R2<=1
Z=np.sqrt(np.clip(1-R2,0,1))
LAT=np.degrees(np.arcsin(np.clip(Y,-1,1))); LON=np.degrees(np.arctan2(X,np.maximum(Z,1e-6)))
lat_r=np.radians(LAT); lon_r=np.radians(LON)
def angdist(lat0,lon0):
    a,b=math.radians(lat0),math.radians(lon0)
    cosd=np.sin(lat_r)*math.sin(a)+np.cos(lat_r)*math.cos(a)*np.cos(lon_r-b)
    return np.degrees(np.arccos(np.clip(cosd,-1,1)))
def bearing(lat0,lon0):
    a,b=math.radians(lat0),math.radians(lon0)
    y=np.sin(lon_r-b)*np.cos(lat_r); x=math.cos(a)*np.sin(lat_r)-math.sin(a)*np.cos(lat_r)*np.cos(lon_r-b)
    return np.arctan2(y,x)
def noise(scale,oct=4,seed=0):
    r=np.random.default_rng(seed);out=np.zeros((S,S),np.float32);amp=1;tot=0
    for o in range(oct):
        n=max(2,int(S/scale*(2**o)));g=r.standard_normal((n,n)).astype(np.float32)
        up=zoom(g,S/n,order=3)[:S,:S];out+=amp*up;tot+=amp;amp*=0.5
    return out/tot
def smooth(a,b,x):t=np.clip((x-a)/(b-a),0,1);return t*t*(3-2*t)

# ---- maria (real near-side positions, lat, lon, radius deg, albedo)
MARIA=[(33,-16,17,0.40),(28,17,9.5,0.47),(8,30,11,0.38),(2,24,7,0.38),(17,59,8,0.40),(-8,51,9,0.43),(-2,55,6,0.43),
 (-15,34,5,0.44),(-20,-17,10,0.44),(-24,-39,6,0.41),(-10,-23,6,0.43),(8,-30,8,0.42),(13,4,4,0.45),(2,1,3,0.46),
 (25,-55,16,0.38),(10,-60,14,0.37),(-2,-46,12,0.39),(38,-45,11,0.39),(-12,-55,8,0.40),(45,-58,7,0.40),
 (56,-35,6,0.44),(57,-15,6,0.44),(56,5,6,0.45),(55,25,5,0.46),(-3,86,6,0.42),(14,-87,4,0.42)]
edgeN=noise(40,5,1)+0.5*noise(12,3,7)
mare=np.zeros((S,S),np.float32); malb=np.zeros((S,S),np.float32)
for la,lo,rad,al in MARIA:
    d=angdist(la,lo); e=rad*(1+0.42*edgeN)
    m=1-smooth(e-3.2,e+1.2,d)
    upd=m>mare; malb=np.where(upd,al,malb); mare=np.maximum(mare,m)
alb=0.60+0.07*noise(50,5,2)+0.04*noise(8,3,3)+0.012*noise(2.5,2,13)+0.04*np.clip(-Y,0,1)
malb=malb*0.72+0.05*noise(25,5,4)+0.025*noise(6,3,5)+0.01*noise(2.5,2,14)
alb=alb*(1-mare)+malb*mare
H=0.45*noise(8,4,6)*(1-0.75*mare)+0.08*noise(2,2,15)   # highland roughness

# ---- craters
def stamp(lat0,lon0,rdeg,depth=1.0,fresh=0.0,floor=None):
    a,b=math.radians(lat0),math.radians(lon0)
    xc=math.cos(a)*math.sin(b); yc=math.sin(a); zc=math.cos(a)*math.cos(b)
    if zc<0.04: return
    px=c+xc*R; py=c-yc*R; rr=math.sin(math.radians(rdeg))*R
    ext=int(rr*2.6)+3; x0,x1=max(0,int(px-ext)),min(S,int(px+ext)+1); y0,y1=max(0,int(py-ext)),min(S,int(py+ext)+1)
    if x0>=x1 or y0>=y1: return
    vx=xx[y0:y1,x0:x1]-px; vy=yy[y0:y1,x0:x1]-py
    L=math.hypot(xc,yc)
    ux,uy=(xc/L,-yc/L) if L>1e-6 else (1,0)
    ra=(vx*ux+vy*uy)/max(zc,0.06); ta=-vx*uy+vy*ux
    rho=np.sqrt(ra*ra+ta*ta)/max(rr,0.5)
    dep=depth*rr*0.24
    h=np.where(rho<1,-dep*(1-rho**2),0)+dep*0.45*np.exp(-((rho-1)/0.25)**2)
    if rr>9: h+=dep*0.35*np.exp(-(rho/0.13)**2)
    H[y0:y1,x0:x1]+=h
    alb[y0:y1,x0:x1]+=0.045*np.exp(-((rho-1.0)/0.22)**2)-0.025*(rho<0.85)
    if fresh>0: alb[y0:y1,x0:x1]+=fresh*(0.22*np.exp(-((rho-1.0)/0.5)**2)+0.10*np.exp(-(rho/1.4)**2))
    if floor is not None: alb[y0:y1,x0:x1]=np.where(rho<0.9,alb[y0:y1,x0:x1]*0.3+floor*0.7,alb[y0:y1,x0:x1])
n=0
while n<5200:
    la=math.degrees(math.asin(rng.uniform(-1,1))); lo=rng.uniform(-90,90)
    r=0.07*(1-rng.random())**(-1/1.9); r=min(r,3.2)
    iy=int(c-math.sin(math.radians(la))*R); ix=int(c+math.cos(math.radians(la))*math.sin(math.radians(lo))*R)
    if 0<=iy<S and 0<=ix<S and mare[iy,ix]>0.5 and rng.random()>0.18: continue
    stamp(la,lo,r,depth=rng.uniform(0.35,0.9),fresh=(0.7 if (rng.random()<0.25 and r<0.6) else 0)); n+=1
NAMED=[(9.6,-20.1,1.5,1.2,1.0,None),(-43.3,-11.4,1.4,1.3,1.2,None),(8.1,-38,0.55,1,1,None),(23.7,-47.4,0.6,1,1.6,None),
 (51.6,-9.4,1.7,0.5,0,0.33),(-58.4,-14.4,3.8,0.8,0,None),(-11.4,26.4,1.6,1.1,0.3,None),(-9.3,-1.9,2.5,0.5,0,None),
 (-5.5,-68.3,2.8,0.5,0,0.30),(-8.9,61,2.2,1,0.4,None),(-25,60,2.9,0.9,0,None),(-13.7,-3.1,1.9,0.9,0,None),(-18.2,-1.9,1.6,0.9,0,None),
 (-11.2,4.1,2.1,0.8,0,None),(-28,-7,1.8,0.8,0,None),(-36,-2,1.5,0.9,0,None),(26,-3,1.2,0.9,0.4,None),(-50,8,2.2,0.9,0,None)]
for la,lo,r,dp,fr,fl in NAMED: stamp(la,lo,r,dp,fr,fl)
# ---- ray systems (Tycho, Copernicus, Kepler, Aristarchus)
for la,lo,cnt,length,amp in [(-43.3,-11.4,60,36,0.2),(9.6,-20.1,48,15,0.16),(8.1,-38,28,9,0.12),(23.7,-47.4,22,6,0.13),(-11.4,26.4,12,5,0.06),(-8.9,61,12,6,0.07)]:
    d=angdist(la,lo); bt=bearing(la,lo); ray=np.zeros((S,S),np.float32)
    for k in range(cnt):
        th=rng.uniform(-math.pi,math.pi); w=rng.uniform(0.12,0.4); Lk=length*rng.uniform(0.5,1.2)
        dif=np.angle(np.exp(1j*(bt-th))); lat_=np.abs(dif)*np.sin(np.radians(d))*57.3
        ray+=np.exp(-(lat_/w)**2)*np.exp(-d/Lk)*smooth(2,5,d)*rng.uniform(0.4,1)
    alb+=amp*np.clip(ray,0,1.5)*np.clip(0.55+0.9*noise(9,3,k+20),0,1.4)
# tiny bright specks
for _ in range(4500):
    iy,ix=rng.integers(0,S,2)
    if inside[iy,ix]: alb[iy,ix]+=rng.uniform(0.08,0.3)
alb=gaussian_filter(alb,0.5); alb=alb+0.45*(alb-gaussian_filter(alb,2.5))
alb=np.clip(alb,0.05,1)
# ---- normals from height (image space) blended with sphere normal
Hs=gaussian_filter(H,0.7); gy,gx=np.gradient(Hs)
k=0.85
nx=X-k*gx*Z; ny=Y+k*gy*Z; nz=Z.copy()
ln=np.sqrt(nx*nx+ny*ny+nz*nz)+1e-6; nx/=ln; ny/=ln; nz/=ln
aa=np.clip(R-np.sqrt((xx-c)**2+(yy-c)**2)+0.5,0,1)   # anti-aliased edge
# ---- save maps for the app
Image.fromarray(np.dstack([(alb*255).astype(np.uint8)]*3+[(aa*255).astype(np.uint8)]),'RGBA').save('moon-albedo.png',optimize=True)
Image.fromarray(np.dstack([((nx*0.5+0.5)*255).astype(np.uint8),((ny*0.5+0.5)*255).astype(np.uint8),((nz*0.5+0.5)*255).astype(np.uint8),(aa*255).astype(np.uint8)]),'RGBA').save('moon-normal.png',optimize=True)
np.savez_compressed('maps.npz',alb=alb,nx=nx,ny=ny,nz=nz,aa=aa)

def render(phase_angle_deg,waxing=True,size=600,tint=None,earthshine=0.035,name='out.png'):
    i=math.radians(phase_angle_deg); s=1 if waxing else -1
    L=(s*math.sin(i),0.0,math.cos(i))
    mu0=nx*L[0]+ny*L[1]+nz*L[2]; mu=np.maximum(nz,0.02)
    mu0c=np.clip(mu0,0,1)
    ls=2*mu0c/(mu0c+mu+1e-6)
    I=alb*(0.65*ls+0.35*mu0c)*smooth(-0.02,0.03,mu0)
    sph=X*L[0]+Y*L[1]+Z*L[2]   # smooth terminator mask on the sphere (plus relief)
    I=I*smooth(-0.04,0.02,sph+0.6*(mu0-sph))
    I=I+earthshine*alb*(1-smooth(-0.05,0.05,sph))
    I=np.clip(I*1.14,0,1)**0.95
    rgb=np.dstack([I,I,I])
    if tint is not None: rgb=rgb*np.array(tint)[None,None,:]
    img=np.dstack([(np.clip(rgb,0,1)*255).astype(np.uint8),(aa*255).astype(np.uint8)])
    Image.fromarray(img,'RGBA').resize((size,size),Image.LANCZOS).save(name,optimize=True)
if __name__=='__main__':
    import sys
    render(38,True,600,None,0.0,'preview-gibbous.png')
    render(118,True,600,None,0.025,'preview-crescent.png')
    print('done')
