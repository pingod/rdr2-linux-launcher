/* RDR2 launcher-bypass shim.
 * Build: clang --target=x86_64-windows-gnu -nostdlib -nodefaultlibs -fuse-ld=lld \
 *        -Wl,--entry,mainCRTStartup -o Launcher.exe shim.c libshim3.a
 * Behaviour: create \\\\.\\pipe\\RDR2Launcher_Pipe (server), spawn RDR2.exe from
 * the same folder, accept one connection, read INIT:..., reply TINI:launcher:<payload>.
 * RDR2's ERR_NO_LAUNCHER check keys off parent image name == "Launcher.exe".
 */
typedef unsigned int u32; typedef unsigned long long u64;
typedef void* HANDLE; typedef unsigned long DWORD; typedef int BOOL; typedef unsigned char BYTE;
typedef struct { u32 cb; void* a; char* d; char* t; u32 x,y,xs,ys,xc,yc,fill,flags,wshow,cbr; BYTE*r; HANDLE i,o,e; } SI_;
typedef struct { HANDLE hp,ht; u32 pid,tid; } PI_;
__declspec(dllimport) HANDLE __stdcall CreateFileA(const char*,DWORD,DWORD,void*,DWORD,DWORD,void*);
__declspec(dllimport) int __stdcall WriteFile(HANDLE,void*,DWORD,DWORD*,void*);
__declspec(dllimport) int __stdcall CloseHandle(HANDLE);
__declspec(dllimport) DWORD __stdcall SetFilePointer(HANDLE,long,long*,DWORD);
__declspec(dllimport) HANDLE __stdcall CreateNamedPipeA(const char*,DWORD,DWORD,DWORD,DWORD,DWORD,DWORD,void*);
__declspec(dllimport) BOOL __stdcall ConnectNamedPipe(HANDLE,void*);
__declspec(dllimport) BOOL __stdcall DisconnectNamedPipe(HANDLE);
__declspec(dllimport) BOOL __stdcall ReadFile(HANDLE,void*,DWORD,DWORD*,void*);
__declspec(dllimport) BOOL __stdcall CreateProcessA(const char*,char*,void*,void*,BOOL,DWORD,void*,const char*,SI_*,PI_*);
__declspec(dllimport) DWORD __stdcall WaitForSingleObject(HANDLE,DWORD);
__declspec(dllimport) BOOL __stdcall GetExitCodeProcess(HANDLE,DWORD*);
__declspec(dllimport) void __stdcall ExitProcess(DWORD);
__declspec(dllimport) HANDLE __stdcall CreateThread(void*,unsigned long long,void*,void*,DWORD,void*);
__declspec(dllimport) DWORD __stdcall GetLastError(void);
__declspec(dllimport) DWORD __stdcall GetModuleFileNameA(HANDLE,char*,DWORD);
static char g_dir[1024]; static char g_rdr2[1200]; static char g_log[1200]; static char g_cwd[1200];
static void wlog(const char* s,int n){HANDLE h=CreateFileA(g_log,0x40000000,3,(void*)0,4,0x80,(void*)0);if(!h||h==(HANDLE)-1)return;SetFilePointer(h,0,(long*)0,2);DWORD wr=0;WriteFile(h,(void*)s,n,&wr,(void*)0);CloseHandle(h);}
static int slen(const char*s){int n=0;while(s[n])n++;return n;}
static void lt(const char*s){wlog(s,slen(s));}
static void lh(u64 v){char b[18];const char*H="0123456789abcdef";for(int i=0;i<16;i++)b[i]=H[(v>>((15-i)*4))&0xf];b[16]='\n';wlog(b,17);}
static void buflog(const char*t,const char*b,int n){lt(t);lt(" len=");char nb[16];int k=0,x=n;if(!x)nb[k++]='0';char t2[16];int m=0;while(x){t2[m++]='0'+x%10;x/=10;}while(m)nb[k++]=t2[--m];nb[k++]='\n';wlog(nb,k);wlog(b,n);lt("\n");}
static void build_paths(void){
  /* dir = folder containing this exe + backslash */
  DWORD n=GetModuleFileNameA((HANDLE)0,g_dir,sizeof(g_dir));
  int i=n-1; while(i>=0 && g_dir[i]!='\\' && g_dir[i]!='/') i--;
  if(i>=0) g_dir[i+1]=0; else g_dir[0]=0;
  int d=slen(g_dir), j=0;
  /* default rdr2 = dir + "RDR2.exe" */
  for(int k=0;k<d;k++) g_rdr2[j++]=g_dir[k];
  const char* R="RDR2.exe"; for(int k=0;R[k];k++) g_rdr2[j++]=R[k]; g_rdr2[j]=0;
  /* log = dir + "rdr2shim.log" */
  j=0; for(int k=0;k<d;k++) g_log[j++]=g_dir[k];
  const char* L="rdr2shim.log"; for(int k=0;L[k];k++) g_log[j++]=L[k]; g_log[j]=0;
  /* override: if a file "rdr2path.txt" sits next to this exe, read the first
     line as the absolute (Windows) path to RDR2.exe and use it instead. */
  static char cfgp[1200]; int c=0;
  for(int k=0;k<d;k++) cfgp[c++]=g_dir[k];
  const char* C="rdr2path.txt"; for(int k=0;C[k];k++) cfgp[c++]=C[k]; cfgp[c]=0;
  HANDLE h=CreateFileA(cfgp,0x80000000,3,(void*)0,3,0x80,(void*)0); /* GENERIC_READ, OPEN_EXISTING */
  if(h && h!=(HANDLE)-1){
    static char cb[1200]; DWORD rd=0;
    if(ReadFile(h,cb,sizeof(cb)-1,&rd,(void*)0) && rd>0){
      /* strip CR/LF/spaces */
      int e=0; while(e<(int)rd && cb[e]!='\r' && cb[e]!='\n') e++;
      while(e>0 && (cb[e-1]==' '||cb[e-1]=='\t')) e--;
      cb[e]=0;
      if(e>3){ int k=0; for(;k<e;k++) g_rdr2[k]=cb[k]; g_rdr2[k]=0; }
    }
    CloseHandle(h);
  }
  /* working directory = folder that contains RDR2.exe (RDR2 loads data by
     relative paths like "update/x64/...", so cwd MUST be the game dir) */
  int last=-1, n2=slen(g_rdr2);
  for(int k=0;k<n2;k++){ if(g_rdr2[k]=='\\'||g_rdr2[k]=='/') last=k; }
  if(last>=0){ int k=0; for(;k<=last;k++) g_cwd[k]=g_rdr2[k]; g_cwd[k]=0; }
  else { int k=0; for(;k<(int)d;k++) g_cwd[k]=g_dir[k]; g_cwd[k]=0; }
}
static HANDLE g_hp;
static DWORD __attribute__((stdcall)) pipeThread(void* x){
  static char buf[0x2000]; int round;
  for(round=0; round<8; round++){
    BOOL c=ConnectNamedPipe(g_hp,(void*)0); DWORD err=GetLastError();
    lt("ConnectNamedPipe="); lh((u64)c); lt("lastErr="); lh((u64)err);
    DWORD n=0; BOOL r=ReadFile(g_hp,buf,0x1000,&n,(void*)0);
    lt("ReadFile="); lh((u64)r); buflog("RECV:",buf,(int)n);
    if(n>=5){ static char rep[0x2000]; const char* T="TINI:launcher:"; int tl=14;
      for(int i=0;i<tl;i++)rep[i]=T[i]; int pl=(int)n-5; for(int i=0;i<pl;i++)rep[tl+i]=buf[5+i];
      DWORD wr=0; WriteFile(g_hp,rep,tl+pl,&wr,(void*)0); buflog("SENT:",rep,tl+pl); }
    DisconnectNamedPipe(g_hp);
  }
  return 0;
}
void* memset(void* d,int c,unsigned long long n){unsigned char*p=(unsigned char*)d;while(n--)*p++=(unsigned char)c;return d;}
int mainCRTStartup(){
  build_paths();
  lt("SHIM START\n"); lt("dir="); lt(g_dir); lt("\nrdr2="); lt(g_rdr2); lt("\n");
  g_hp=CreateNamedPipeA("\\\\.\\pipe\\RDR2Launcher_Pipe", 3|0x80000, 0, 0xff, 0x1000,0x1000,0,(void*)0);
  lt("pipe="); lh((u64)g_hp);
  SI_ si={0}; PI_ pi={0}; si.cb=sizeof(SI_);
  BOOL ok=CreateProcessA(g_rdr2,(char*)"RDR2.exe",(void*)0,(void*)0,0,0,(void*)0,g_cwd,&si,&pi);
  lt("CreateProcess="); lh((u64)ok); lt("pid="); lh((u64)pi.pid);
  CreateThread((void*)0,0,pipeThread,(void*)0,0,(void*)0);
  DWORD w=WaitForSingleObject(pi.hp, 0xFFFFFFFF);
  DWORD ec=0; GetExitCodeProcess(pi.hp,&ec);
  lt("RDR2 wait="); lh((u64)w); lt("RDR2 exit="); lh((u64)ec); lt("SHIM END\n");
  ExitProcess(ec); return (int)ec;
}
