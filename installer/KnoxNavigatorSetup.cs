using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace KnoxNavigatorSetup {
    public sealed class Part { public string name; public string sha256; public long size; }
    public sealed class Manifest { public string version; public string baseUrl; public Part[] parts; public long unpackedBytes; }
    static class Program {
        public static string Repository = "__REPOSITORY__";
        [STAThread] static int Main(string[] args) {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            if (args.Length == 3 && args[0] == "--install-local") {
                try { Install(args[1], args[2], delegate(int p, string s) {}); return 0; }
                catch (Exception ex) { File.WriteAllText(args[2] + ".error.txt", ex.ToString()); return 1; }
            }
            if (args.Length == 3 && args[0] == "--install-zip") {
                string temp=Path.Combine(Path.GetTempPath(),"KnoxNavigator-test-"+Guid.NewGuid().ToString("N"));
                try { Extract(args[1],temp);Install(Path.Combine(temp,"KnoxNavigator"),args[2],delegate(int p,string s) {});return 0; }
                catch (Exception ex) { File.WriteAllText(args[2]+".error.txt",ex.ToString());return 1; }
                finally { DeleteOwned(temp,Path.GetTempPath()); }
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new SetupForm()); return 0;
        }
        public static string DefaultMods { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Zomboid", "mods"); } }
        static void CopyTree(string source, string target) {
            Directory.CreateDirectory(target);
            foreach (string file in Directory.GetFiles(source)) File.Copy(file, Path.Combine(target, Path.GetFileName(file)), true);
            foreach (string dir in Directory.GetDirectories(source)) CopyTree(dir, Path.Combine(target, Path.GetFileName(dir)));
        }
        static void DeleteOwned(string path, string owner) {
            string full = Path.GetFullPath(path), root = Path.GetFullPath(owner).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new IOException("Unsafe cleanup path.");
            if (Directory.Exists(full)) Directory.Delete(full, true);
        }
        public static void Install(string payload, string mods, Action<int,string> report) {
            if (!File.Exists(Path.Combine(payload,"42","mod.info"))) throw new IOException("В архиве отсутствует 42/mod.info.");
            string info=File.ReadAllText(Path.Combine(payload,"42","mod.info"));
            if (!info.Contains("id=KnoxNavigator")) throw new IOException("Архив не содержит Knox Navigator.");
            mods=Path.GetFullPath(mods); Directory.CreateDirectory(mods);
            string target=Path.Combine(mods,"KnoxNavigator");
            if (String.Equals(Path.GetFullPath(payload).TrimEnd('\\'),target.TrimEnd('\\'),StringComparison.OrdinalIgnoreCase)) throw new IOException("Источник совпадает с папкой установки.");
            string stage=Path.Combine(mods,".KnoxNavigator-install-"+Guid.NewGuid().ToString("N"));
            string backup=Path.Combine(mods,".KnoxNavigator-backup-"+Guid.NewGuid().ToString("N"));
            bool moved=false;
            try {
                report(90,"Копирование мода…");CopyTree(payload,stage);
                if (Directory.Exists(target)) { Directory.Move(target,backup); moved=true; }
                try { Directory.Move(stage,target); }
                catch { if (moved) Directory.Move(backup,target); throw; }
                // Keep a recoverable backup of the previous installation.
                report(100,"Установлено: "+target);
            } finally { DeleteOwned(stage,mods); }
        }
        static HttpWebRequest Request(string url) {
            Uri uri=new Uri(url);
            if (uri.Scheme != "https") throw new IOException("Ссылка загрузки должна использовать HTTPS.");
            HttpWebRequest request=(HttpWebRequest)WebRequest.Create(uri);
            request.UserAgent="KnoxNavigatorSetup/1.0";request.Timeout=60000;request.ReadWriteTimeout=60000;
            return request;
        }
        static string Hash(byte[] bytes) { return BitConverter.ToString(bytes).Replace("-","").ToLowerInvariant(); }
        public static void Extract(string archive,string destination) {
            string root=Path.GetFullPath(destination).TrimEnd('\\')+"\\";
            Directory.CreateDirectory(destination);
            using (ZipArchive zip=ZipFile.OpenRead(archive)) {
                foreach (ZipArchiveEntry entry in zip.Entries) {
                    string path=Path.GetFullPath(Path.Combine(destination,entry.FullName.Replace('/', '\\')));
                    if (!path.StartsWith(root,StringComparison.OrdinalIgnoreCase)) throw new IOException("Недопустимый путь внутри архива.");
                    if (String.IsNullOrEmpty(entry.Name)) Directory.CreateDirectory(path);
                    else { Directory.CreateDirectory(Path.GetDirectoryName(path));entry.ExtractToFile(path,true); }
                }
            }
        }
        public static void DownloadAndInstall(string mods,Action<int,string> report) {
            if (Process.GetProcessesByName("ProjectZomboid64").Length>0 || Process.GetProcessesByName("ProjectZomboid32").Length>0)
                throw new IOException("Сначала полностью закройте Project Zomboid и повторите установку.");
            string appDir=AppDomain.CurrentDomain.BaseDirectory;
            string bundled=Path.Combine(appDir,"KnoxNavigator");
            if (Directory.Exists(bundled)) { Install(bundled,mods,report);return; }
            string temporaryRoot=Path.GetTempPath();
            string temporary=Path.Combine(temporaryRoot,"KnoxNavigator-"+Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temporary);
            try {
                string archive=Path.Combine(temporary,"KnoxNavigator.zip");
                string localZip=Path.Combine(appDir,"KnoxNavigator.zip");
                if (File.Exists(localZip)) archive=localZip;
                else {
                    if (Repository.Contains("__")) throw new IOException("Онлайн-релиз ещё не настроен. Положите EXE рядом с KnoxNavigator.zip или папкой KnoxNavigator.");
                    report(0,"Получение последней версии…");
                    string manifestUrl="https://github.com/"+Repository+"/releases/latest/download/manifest.json";
                    Manifest manifest;
                    using (WebResponse response=Request(manifestUrl).GetResponse())
                    using (StreamReader reader=new StreamReader(response.GetResponseStream(),Encoding.UTF8))
                        manifest=new JavaScriptSerializer().Deserialize<Manifest>(reader.ReadToEnd());
                    if (manifest==null || manifest.parts==null || manifest.parts.Length==0) throw new IOException("Неверное описание релиза.");
                    long total=0;foreach (Part part in manifest.parts) { if (part.size<=0 || Path.GetFileName(part.name)!=part.name) throw new IOException("Неверная часть релиза.");total+=part.size; }
                    long downloaded=0;
                    using (FileStream output=File.Create(archive)) {
                        foreach (Part part in manifest.parts) {
                            report((int)(downloaded*70/total),"Загрузка версии "+manifest.version+" — "+part.name);
                            using (WebResponse response=Request(manifest.baseUrl+"/"+Uri.EscapeDataString(part.name)).GetResponse())
                            using (Stream input=response.GetResponseStream())
                            using (SHA256 hash=SHA256.Create()) {
                                byte[] buffer=new byte[1024*1024];int count;long partBytes=0;
                                while ((count=input.Read(buffer,0,buffer.Length))>0) {
                                    hash.TransformBlock(buffer,0,count,buffer,0);output.Write(buffer,0,count);
                                    partBytes+=count;downloaded+=count;
                                    report((int)Math.Min(70,downloaded*70/total),"Загрузка: "+(downloaded/1048576)+" / "+(total/1048576)+" МБ");
                                }
                                hash.TransformFinalBlock(new byte[0],0,0);
                                if (partBytes!=part.size || Hash(hash.Hash)!=part.sha256) throw new IOException("Проверка файла не пройдена: "+part.name+". Повторите установку.");
                            }
                        }
                    }
                }
                report(75,"Распаковка подробных карт…");
                string extracted=Path.Combine(temporary,"unpacked");Extract(archive,extracted);
                Install(Path.Combine(extracted,"KnoxNavigator"),mods,report);
            } finally { DeleteOwned(temporary,temporaryRoot); }
        }
    }
    public sealed class SetupForm : Form {
        TextBox path=new TextBox();Label status=new Label();ProgressBar progress=new ProgressBar();Button install=new Button();Button browse=new Button();
        BackgroundWorker worker=new BackgroundWorker();bool busy=false;
        public SetupForm() {
            Text="Knox Navigator — установка";ClientSize=new Size(590,320);Font=new Font("Segoe UI",10);
            FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;StartPosition=FormStartPosition.CenterScreen;
            Label title=new Label { Text="Knox Navigator",Font=new Font("Segoe UI",20,FontStyle.Bold),Location=new Point(24,18),AutoSize=true };
            Label subtitle=new Label { Text="Навигатор для Project Zomboid Build 42.21",Location=new Point(26,66),AutoSize=true };
            Label hint=new Label { Text="Папка модов (определена автоматически):",Location=new Point(26,105),AutoSize=true };
            path.Text=Program.DefaultMods;path.SetBounds(26,132,435,28);
            browse.Text="Обзор…";browse.SetBounds(470,130,94,31);
            browse.Click+=delegate { using (FolderBrowserDialog dialog=new FolderBrowserDialog()) { dialog.SelectedPath=path.Text;if(dialog.ShowDialog()==DialogResult.OK) path.Text=dialog.SelectedPath; } };
            install.Text="Установить / обновить";install.SetBounds(26,180,538,42);
            progress.SetBounds(26,237,538,14);status.SetBounds(26,263,538,48);
            status.Text="Закройте игру. После установки включите мод в меню игры.\nДанные карты занимают около 3,5 ГБ; на время установки нужно 12 ГБ.";
            Controls.AddRange(new Control[]{title,subtitle,hint,path,browse,install,progress,status});
            worker.WorkerReportsProgress=true;
            worker.DoWork+=delegate(object sender,DoWorkEventArgs e) { Program.DownloadAndInstall((string)e.Argument,delegate(int p,string s){worker.ReportProgress(p,s);}); };
            worker.ProgressChanged+=delegate(object sender,ProgressChangedEventArgs e) { progress.Value=Math.Max(0,Math.Min(100,e.ProgressPercentage));status.Text=(string)e.UserState; };
            worker.RunWorkerCompleted+=delegate(object sender,RunWorkerCompletedEventArgs e) {
                busy=false;install.Enabled=browse.Enabled=path.Enabled=true;
                if(e.Error!=null) { status.Text="Установка не завершена.";MessageBox.Show(this,e.Error.Message,"Knox Navigator",MessageBoxButtons.OK,MessageBoxIcon.Error); }
                else { status.Text="Готово! Включите Knox Navigator в меню «Моды» и в сохранении.\nЗатем загрузите мир и сядьте в машину.";install.Text="Установить повторно"; }
            };
            install.Click+=delegate { busy=true;install.Enabled=browse.Enabled=path.Enabled=false;worker.RunWorkerAsync(path.Text); };
            FormClosing+=delegate(object sender,FormClosingEventArgs e) { if(busy) { e.Cancel=true;MessageBox.Show(this,"Дождитесь окончания установки."); } };
        }
    }
}
