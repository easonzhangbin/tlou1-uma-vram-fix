using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
namespace TlouVram {
 public sealed class Adapter {
  public int Index; public string Name; public uint VendorId,DeviceId;
  public ulong Dedicated,Shared,LocalBudget; public bool Uma,ArchitectureKnown;
  public string ProbeError;
 }
 public sealed class Plan {
  public string Name,State,BeforeHash,AfterHash; public PatchSite[] Sites;
 }
 public sealed class PatchSite { public int Offset; public byte[] Bytes; }
 public static class Fix {
  public const string Version = "2.0.0";
  static readonly byte[] Original = Hex("488b431848d1e8"), Patched=Hex("488b4310909090");
  static readonly string[] Names={"tlou-i.exe","tlou-i-l.exe"};
  static readonly string[] OriginalHashes={"088d37aff3b8e3f65715e7e325547c07e6c4d794966c0573cd0f7af5c6c3503a","3c9284ff5beddebbdec2d127ffb42ad3c488c8eea38c9a29718c32a09cdfbea3"};
  static readonly string[] V1Hashes={"245b1f569533ed709f42a9e4c82e4b1755bdb3d732fa53114617a0e1fcb39824","405c145b1910ffabbac22ab5348dcc4656131c52d3f9dcad6793b221de98784d"};
  static readonly string[] PatchedHashes={"1d65b6c8319d2c713f18fe605e1cd30ffd539f07d1bcb071ccbcb72adc665bc7","c6fa70397e10700754d987aae008eb1b0e75fb946d7913886eb75ee892cd111d"};
  static readonly int[] Offsets={0x206c270,0x20679e0};
  static readonly int[] TextureOffsets={0x10dcb33,0x10ddfc3};
  public static string Hash(byte[] data) { using(var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(data)).Replace("-","").ToLowerInvariant(); }
  public static byte[] Hex(string s) { var b=new byte[s.Length/2]; for(int i=0;i<b.Length;i++) b[i]=Convert.ToByte(s.Substring(i*2,2),16); return b; }
  public static string Eligibility(Adapter a) {
   if(!a.ArchitectureKnown) return "SKIP: UMA architecture could not be verified";
   if(!a.Uma) return "SKIP: discrete/non-UMA adapter";
   if(a.Dedicated<8UL*1024*1024*1024) return "SKIP: v2 requires at least 8 GiB dedicated UMA carve-out";
   if(a.Dedicated<=a.Shared/2 || a.Dedicated-a.Shared/2<64UL*1024*1024) return "SKIP: dedicated carve-out does not materially exceed original fallback";
   if(a.LocalBudget==0) return "SKIP: DXGI local budget query failed";
   if(a.LocalBudget<a.Dedicated) return "SKIP: current OS budget below dedicated carve-out; investigate memory pressure first";
   return "ELIGIBLE";
  }
  public static Plan Inspect(string name,byte[] data,bool restore) {
   int i=Array.IndexOf(Names,name); if(i<0) throw new InvalidDataException("Unexpected game filename");
   string hash=Hash(data); bool isOriginal=hash==OriginalHashes[i],isV1=hash==V1Hashes[i],isPatched=hash==PatchedHashes[i];
   if(!isOriginal&&!isV1&&!isPatched) throw new InvalidDataException(name+": unsupported SHA-256. No fuzzy patching is allowed.");
   int pe=BitConverter.ToInt32(data,0x3c);
   if(data[0]!=0x4d||data[1]!=0x5a||BitConverter.ToUInt32(data,pe)!=0x4550||BitConverter.ToUInt16(data,pe+4)!=0x8664) throw new InvalidDataException("Not an x64 PE image");
   int off=Offsets[i]; byte[] expected=isOriginal?Original:Patched;
   for(int j=0;j<7;j++) if(data[off+j]!=expected[j]) throw new InvalidDataException("Unexpected patch-site bytes");
   int textureOff=TextureOffsets[i]; byte expectedBranch=isPatched?(byte)0xeb:(byte)0x74;
   if(data[textureOff]!=expectedBranch||data[textureOff+1]!=0x0a) throw new InvalidDataException("Unexpected texture-budget branch");
   var sites=new PatchSite[]{new PatchSite{Offset=off,Bytes=restore?Original:Patched},new PatchSite{Offset=textureOff,Bytes=restore?Hex("740a"):Hex("eb0a")}};
   byte[] result=(byte[])data.Clone(); foreach(var site in sites) Array.Copy(site.Bytes,0,result,site.Offset,site.Bytes.Length);
   string wanted=restore?OriginalHashes[i]:PatchedHashes[i];
   if(Hash(result)!=wanted) throw new InvalidDataException("Unexpected output hash");
   return new Plan{Name=name,State=isOriginal?"Original":(isV1?"CapacityOnlyV1":"PatchedV2"),BeforeHash=hash,AfterHash=wanted,Sites=sites};
  }
  static byte[] ReadAll(FileStream stream) {
   stream.Position=0; if(stream.Length>int.MaxValue) throw new InvalidDataException("File too large");
   byte[] data=new byte[(int)stream.Length]; int n=0; while(n<data.Length) { int r=stream.Read(data,n,data.Length-n); if(r==0) throw new EndOfStreamException(); n+=r; } return data;
  }
  // Both targets stay exclusively locked through validation, backup, write and verification.
  public static string Apply(string directory,bool restore) {
   string root=Path.GetFullPath(directory); var streams=new List<FileStream>(); var plans=new List<Plan>();
   var inputs=new List<byte[]>(); string backup=null; bool writing=false;
   try {
    foreach(string name in Names) streams.Add(new FileStream(Path.Combine(root,name),FileMode.Open,FileAccess.ReadWrite,FileShare.None));
    for(int i=0;i<Names.Length;i++) { var data=ReadAll(streams[i]); inputs.Add(data); plans.Add(Inspect(Names[i],data,restore)); }
    if(plans.TrueForAll(p=>p.BeforeHash==p.AfterHash)) return "Already in requested state; no changes.";
    backup=Path.Combine(root,"tlou-vram-backups",DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N")); Directory.CreateDirectory(backup);
    var info=new List<string>();
    for(int i=0;i<Names.Length;i++) { string path=Path.Combine(backup,Names[i]); File.WriteAllBytes(path,inputs[i]); if(Hash(File.ReadAllBytes(path))!=plans[i].BeforeHash) throw new IOException("Backup verification failed"); info.Add(Names[i]+" before="+plans[i].BeforeHash+" after="+plans[i].AfterHash); }
    File.WriteAllLines(Path.Combine(backup,"hashes.txt"),info.ToArray());
    writing=true;
    for(int i=0;i<Names.Length;i++) {
     if(plans[i].BeforeHash==plans[i].AfterHash) continue;
     foreach(var site in plans[i].Sites) { streams[i].Position=site.Offset; streams[i].Write(site.Bytes,0,site.Bytes.Length); } streams[i].Flush(true);
     if(Hash(ReadAll(streams[i]))!=plans[i].AfterHash) throw new IOException("Post-write verification failed");
    }
    return "SUCCESS. Verified backup: "+backup;
   } catch(Exception failure) {
    if(writing) {
     var errors=new List<Exception>(); errors.Add(failure);
     for(int i=0;i<inputs.Count;i++) try { streams[i].Position=0; streams[i].Write(inputs[i],0,inputs[i].Length); streams[i].Flush(true); if(Hash(ReadAll(streams[i]))!=plans[i].BeforeHash) throw new IOException("Rollback hash mismatch"); } catch(Exception rollback) { errors.Add(rollback); }
     if(errors.Count>1) throw new AggregateException("Rollback incomplete. Preserve backup: "+backup,errors);
    }
    throw;
   } finally { foreach(var stream in streams) stream.Dispose(); }
  }
 }
 public static class Hardware {
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Desc { [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string Name; public uint Vendor,Device,Subsys,Revision; public UIntPtr Dedicated,System,Shared; public uint LuidLow; public int LuidHigh; public uint Flags; }
  [StructLayout(LayoutKind.Sequential)] struct Architecture { public uint Node; public int Tile,Uma,Coherent,Isolated; }
  [StructLayout(LayoutKind.Sequential)] struct MemoryInfo { public ulong Budget,Usage,Available,Reservation; }
  [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid iid,out IntPtr factory);
  [DllImport("d3d12.dll")] static extern int D3D12CreateDevice(IntPtr adapter,int level,ref Guid iid,out IntPtr device);
  [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int EnumAdapters(IntPtr self,uint index,out IntPtr adapter);
  [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetDesc(IntPtr self,out Desc desc);
  [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int CheckFeature(IntPtr self,int feature,ref Architecture arch,uint size);
  [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int QueryMemory(IntPtr self,uint node,int group,out MemoryInfo memory);
  [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int QueryInterface(IntPtr self,ref Guid iid,out IntPtr result);
  static T Method<T>(IntPtr p,int slot) { return (T)(object)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(p),slot*IntPtr.Size),typeof(T)); }
  public static Adapter[] Probe() {
   if(IntPtr.Size!=8) throw new PlatformNotSupportedException("Use 64-bit PowerShell");
   Guid fi=new Guid("770aae78-f26f-4dba-a829-253c83d1b387"); IntPtr f; Marshal.ThrowExceptionForHR(CreateDXGIFactory1(ref fi,out f)); var result=new List<Adapter>();
   try { for(uint i=0;;i++) { IntPtr a; int hr=Method<EnumAdapters>(f,12)(f,i,out a); if(hr==unchecked((int)0x887a0002)) break; Marshal.ThrowExceptionForHR(hr);
    try {
     Desc d; Marshal.ThrowExceptionForHR(Method<GetDesc>(a,10)(a,out d)); if((d.Flags&2)!=0) continue;
     var adapter=new Adapter{Index=(int)i,Name=d.Name,VendorId=d.Vendor,DeviceId=d.Device,Dedicated=d.Dedicated.ToUInt64(),Shared=d.Shared.ToUInt64()};
     IntPtr device; Guid di=new Guid("189819f1-1db6-4b57-be54-1821339b85f7"); hr=D3D12CreateDevice(a,0xc000,ref di,out device);
     if(hr>=0) { try { var arch=new Architecture(); hr=Method<CheckFeature>(device,13)(device,16,ref arch,(uint)Marshal.SizeOf(typeof(Architecture))); if(hr>=0) {adapter.ArchitectureKnown=true; adapter.Uma=arch.Uma!=0;} else adapter.ProbeError="Architecture HRESULT "+hr; } finally { Marshal.Release(device); } } else adapter.ProbeError="D3D12 HRESULT "+hr;
     Guid a3i=new Guid("645967a4-1392-4310-a798-8053ce3e93fd"); IntPtr a3;
     if(Method<QueryInterface>(a,0)(a,ref a3i,out a3)>=0) { try { MemoryInfo m; if(Method<QueryMemory>(a3,14)(a3,0,0,out m)>=0) adapter.LocalBudget=m.Budget; } finally {Marshal.Release(a3);} }
     result.Add(adapter);
    } finally {Marshal.Release(a);}
   }} finally {Marshal.Release(f);} return result.ToArray();
  }
 }
}
