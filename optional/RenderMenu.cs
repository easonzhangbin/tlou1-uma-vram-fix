using System;
using System.IO;
using System.Security.Cryptography;

namespace TlouDiagnostics {
 public static class RenderMenu {
  public const string BaseHash = "1d65b6c8319d2c713f18fe605e1cd30ffd539f07d1bcb071ccbcb72adc665bc7";
  public const string UnlockedHash = "f1c474f05ef998b122968b68a540704c0a513bab284cbfad3ad859af95a73942";
  static readonly int[] Offsets = {0x5d5b5b,0x5d5dab,0x2c55d74,0x2c55d78,0x2c556b8,0x2c55ef8};
  static readonly string[] Before = {"0f84e8010000","0f84040b0000","0a000000","0000000300000000","0050830000000000","0010d21800000000"};
  static readonly string[] After = {"909090909090","909090909090","05000000","0000400000000000","0050430000000000","0010d21b00000000"};
  public static string Hash(byte[] data) {
   using(var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(data)).Replace("-","").ToLowerInvariant();
  }
  static byte[] Hex(string text) {
   var result=new byte[text.Length/2];
   for(int i=0;i<result.Length;i++) result[i]=Convert.ToByte(text.Substring(i*2,2),16);
   return result;
  }
  public static string Inspect(byte[] data) {
   string hash=Hash(data);
   if(hash!=BaseHash && hash!=UnlockedHash) throw new InvalidDataException("Unsupported SHA-256. Requires the exact v2 tlou-i.exe; no force or partial-patch mode.");
   for(int i=0;i<Offsets.Length;i++) {
    var expected=Hex(hash==BaseHash?Before[i]:After[i]);
    for(int j=0;j<expected.Length;j++) if(data[Offsets[i]+j]!=expected[j]) throw new InvalidDataException("Unexpected patch-site bytes.");
   }
   return hash==BaseHash?"BaseV2":"RenderMenuUnlocked";
  }
  static byte[] ReadAll(FileStream stream) {
   stream.Position=0;
   if(stream.Length>int.MaxValue) throw new InvalidDataException("File too large.");
   var result=new byte[(int)stream.Length]; int n=0;
   while(n<result.Length) { int read=stream.Read(result,n,result.Length-n); if(read==0) throw new EndOfStreamException(); n+=read; }
   return result;
  }
  public static string Diagnose(string directory) {
   using(var stream=new FileStream(Path.Combine(Path.GetFullPath(directory),"tlou-i.exe"),FileMode.Open,FileAccess.Read,FileShare.Read)) return Inspect(ReadAll(stream));
  }
  public static string Apply(string directory,bool restore) {
   string root=Path.GetFullPath(directory), backup=null;
   using(var stream=new FileStream(Path.Combine(root,"tlou-i.exe"),FileMode.Open,FileAccess.ReadWrite,FileShare.None)) {
    var input=ReadAll(stream); Inspect(input);
    string beforeHash=Hash(input), wanted=restore?BaseHash:UnlockedHash;
    if(beforeHash==wanted) return "Already in requested state; no changes.";
    var output=(byte[])input.Clone();
    for(int i=0;i<Offsets.Length;i++) { var bytes=Hex(restore?Before[i]:After[i]); Array.Copy(bytes,0,output,Offsets[i],bytes.Length); }
    if(Hash(output)!=wanted) throw new InvalidDataException("Unexpected output SHA-256.");
    backup=Path.Combine(root,"tlou-render-menu-backups",DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(backup);
    string backupFile=Path.Combine(backup,"tlou-i.exe");
    File.WriteAllBytes(backupFile,input);
    if(Hash(File.ReadAllBytes(backupFile))!=beforeHash) throw new IOException("Backup verification failed.");
    File.WriteAllText(Path.Combine(backup,"hashes.txt"),"before="+beforeHash+Environment.NewLine+"after="+wanted+Environment.NewLine);
    try {
     for(int i=0;i<Offsets.Length;i++) { var bytes=Hex(restore?Before[i]:After[i]); stream.Position=Offsets[i]; stream.Write(bytes,0,bytes.Length); }
     stream.Flush(true);
     if(Hash(ReadAll(stream))!=wanted) throw new IOException("Post-write verification failed.");
    } catch(Exception failure) {
     try {
      stream.Position=0; stream.Write(input,0,input.Length); stream.Flush(true);
      if(Hash(ReadAll(stream))!=beforeHash) throw new IOException("Rollback SHA-256 mismatch.");
     } catch(Exception rollback) { throw new AggregateException("Rollback incomplete. Preserve backup: "+backup,failure,rollback); }
     throw;
    }
    return "SUCCESS. Verified backup: "+backup;
   }
  }
 }
}
