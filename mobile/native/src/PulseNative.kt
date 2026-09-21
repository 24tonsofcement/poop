package org.pulsefour.nativeimport

import android.app.*
import android.content.*
import android.net.Uri
import android.os.*
import android.provider.DocumentsContract
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.widget.EditText
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.ffmpeg.FFmpeg
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class PulseNative(godot: Godot): GodotPlugin(godot) {
    override fun getPluginName() = "PulseNative"
    private val executor = Executors.newSingleThreadExecutor()
    private val cancelled = AtomicBoolean(false)
    private val busy = AtomicBoolean(false)
    @Volatile private var status = "{\"state\":\"idle\",\"message\":\"Ready for on-device generation\"}"
    @Volatile private var process: java.lang.Process? = null
    private var library = ""
    private var exportFile: File? = null
    private val context get() = requireNotNull(activity).applicationContext
    private val prefs get() = context.getSharedPreferences("private_import",Context.MODE_PRIVATE)
    override fun onMainCreate(activity: Activity): android.view.View? {
        if(activity.intent.getBooleanExtra("pulse_native_test",false)) {
            executor.execute {
                try { initialize(); val result=Python.getInstance().getModule("native_import").callAttr("self_test",this).toString()
                    android.util.Log.i("PulseNativeTest",result)
                    File(context.filesDir,"native-test-result").writeText("PASS: $result")
                } catch(e:Exception){File(context.filesDir,"native-test-result").writeText("FAIL: ${e.javaClass.simpleName}: ${e.message}")}
            }
        }
        val probe=activity.intent.getStringExtra("pulse_update_probe")
        if(probe=="seed"||probe=="check")executor.execute {
            val result=File(context.filesDir,"update-probe-result")
            try {
                val probePrefs=context.getSharedPreferences("update_probe",Context.MODE_PRIVATE)
                val cipher=Cipher.getInstance("AES/GCM/NoPadding")
                if(probe=="seed") {
                    cipher.init(Cipher.ENCRYPT_MODE,key("pulse-update-probe"))
                    check(probePrefs.edit().putString("iv",Base64.encodeToString(cipher.iv,Base64.NO_WRAP))
                        .putString("encrypted",Base64.encodeToString(cipher.doFinal("update-preserves-encrypted-settings".toByteArray()),Base64.NO_WRAP)).commit())
                }else{
                    cipher.init(Cipher.DECRYPT_MODE,key("pulse-update-probe"),GCMParameterSpec(128,Base64.decode(probePrefs.getString("iv","")!!,Base64.NO_WRAP)))
                    check(String(cipher.doFinal(Base64.decode(probePrefs.getString("encrypted","")!!,Base64.NO_WRAP)))=="update-preserves-encrypted-settings")
                }
                result.writeText("PASS: encrypted preferences and Android Keystore "+probe)
            }catch(e:Exception){result.writeText("FAIL: "+e.javaClass.simpleName)}
        }
        return null
    }
    @UsedByGodot fun get_status() = status
    @UsedByGodot fun has_key() = prefs.contains("credential")
    @UsedByGodot fun get_model() = prefs.getString("model","") ?: ""
    @UsedByGodot fun set_model(value:String) { prefs.edit().putString("model",value.trim()).apply() }
    @UsedByGodot fun cancel() { cancelled.set(true); process?.destroy(); YoutubeDL.destroyProcessById("pulse-import") }
    @UsedByGodot fun clear_key() {prefs.edit().remove("credential").remove("iv").apply()}
    @UsedByGodot fun enter_key() {
        activity?.runOnUiThread {
            val input=EditText(activity);input.inputType=129;input.hint="New Anthropic API key"
            AlertDialog.Builder(activity).setTitle("Private API key — stored on this device")
                .setMessage("AI sends measured song features and chart patterns to Anthropic. API usage is billed to this key. It is never included in song cards.")
                .setView(input).setNegativeButton("Cancel",null).setPositiveButton("Save") {_,_->
                    val value=input.text.toString().trim()
                    if(value.startsWith("sk-ant-")){saveKey(value);progress("API key saved privately",0.0)}
                    else progress("That does not look like an Anthropic API key",0.0)
                    input.text.clear()
                }.show()
        }
    }
    private fun key(alias:String = "pulse-anthropic"): SecretKey {
        val store=KeyStore.getInstance("AndroidKeyStore");store.load(null)
        (store.getKey(alias,null) as? SecretKey)?.let{return it}
        val generator=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        return generator.generateKey()
    }
    private fun saveKey(value:String) {
        val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key())
        prefs.edit().putString("iv",Base64.encodeToString(cipher.iv,Base64.NO_WRAP))
            .putString("credential",Base64.encodeToString(cipher.doFinal(value.toByteArray()),Base64.NO_WRAP)).apply()
    }
    private fun readKey():String {
        val iv=prefs.getString("iv",null)?:throw IllegalStateException("Enter an API key in Settings > AI")
        val encrypted=prefs.getString("credential",null)?:throw IllegalStateException("Missing API key")
        val cipher=Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,Base64.decode(iv,Base64.NO_WRAP)))
        return String(cipher.doFinal(Base64.decode(encrypted,Base64.NO_WRAP)))
    }
    fun api(path:String,body:String):String {
        require(path=="/v1/messages"||path=="/v1/models")
        val connection=URL("https://api.anthropic.com$path").openConnection() as HttpURLConnection
        try {
            connection.connectTimeout=30000;connection.readTimeout=180000
            connection.setRequestProperty("x-api-key",readKey());connection.setRequestProperty("anthropic-version","2023-06-01")
            if(body.isNotEmpty()){connection.requestMethod="POST";connection.doOutput=true;connection.setRequestProperty("Content-Type","application/json");connection.outputStream.use{it.write(body.toByteArray())}}
            val code=connection.responseCode
            if(code!=200)throw IllegalStateException("Claude request returned HTTP $code. Check model access, credit and connection.")
            return connection.inputStream.bufferedReader().use{it.readText()}
        }finally{connection.disconnect()}
    }
    @UsedByGodot fun update_downloader() {
        executor.execute {try {initialize();progress("Updating the bundled downloader…",0.0);YoutubeDL.updateYoutubeDL(context);progress("Downloader is up to date",100.0)}catch(e:Exception){fail(e)}}
    }
    @UsedByGodot fun list_models() {
        executor.execute {try {val data=JSONObject(api("/v1/models","")); status=JSONObject().put("state","models").put("models",data.getJSONArray("data")).put("message","Choose the exact model available to your account").toString()}
        catch(e:Exception){fail(e)}}
    }
    fun isCancelled()=cancelled.get()
    fun progress(message:String,value:Double) {status=JSONObject().put("state",if(busy.get())"working" else "idle").put("message",message).put("progress",value).toString()}
    private fun fail(e:Exception) {status=JSONObject().put("state","error").put("message",e.message?.take(900)?:"Import failed").toString()}
    fun binary(name:String):String = File(context.applicationInfo.nativeLibraryDir, when(name){"ffmpeg"->"libffmpeg.so";"demucs"->"libpulse_demucs.so";else->throw IllegalArgumentException("Unknown tool")}).absolutePath
    fun modelPath():String {
        val file=File(context.noBackupFilesDir,"htdemucs-6s-f16.bin")
        if(!file.exists()) {
            val partial=File(file.path+".partial")
            context.assets.open("htdemucs-6s-f16.bin").use{source->partial.outputStream().use{source.copyTo(it)}}
            check(partial.renameTo(file)){"Cannot install bundled separation model"}
        }
        return file.path
    }
    private fun initialize() {
        if(!Python.isStarted()) Python.start(AndroidPlatform(context))
        YoutubeDL.init(context);FFmpeg.init(context)
    }
    fun command(raw:String) {
        if(cancelled.get())throw IllegalStateException("Import cancelled")
        val array=JSONArray(raw);val args=(0 until array.length()).map{array.getString(it)}
        require(args.first()==binary("ffmpeg")||args.first()==binary("demucs"))
        val builder=ProcessBuilder(args).redirectErrorStream(true)
        builder.environment()["LD_LIBRARY_PATH"]=File(context.noBackupFilesDir,"youtubedl-android/packages/python/usr/lib").path+":"+File(context.noBackupFilesDir,"youtubedl-android/packages/ffmpeg/usr/lib").path+":"+context.applicationInfo.nativeLibraryDir
        builder.environment()["OMP_NUM_THREADS"]="2"
        val child=builder.start();process=child
        val tail=StringBuilder()
        try {
            child.inputStream.bufferedReader().useLines {lines->lines.forEach{line->
                if(line.startsWith("PROGRESS "))progress("Separating instruments: "+(line.substringAfter(' ').toFloatOrNull()?.times(100)?.toInt()?:0)+"%",35.0)
                if(tail.length>3000)tail.delete(0,tail.length-2000);tail.append(line).append('\n')
                if(cancelled.get())child.destroy()
            }}
            if(child.waitFor()!=0)throw IllegalStateException(if(cancelled.get())"Import cancelled" else "Audio tool failed: ${tail.takeLast(1600)}")
        }finally{child.destroy();process=null}
    }
    // Never inherit Chaquopy's PYTHONPATH into the separate downloader interpreter.
    private fun downloaderProcess(arguments:List<String>, pythonCode:Boolean=false):String {
        val runtime=File(context.noBackupFilesDir,"youtubedl-android/packages/python/usr")
        val bin=File(context.applicationInfo.nativeLibraryDir)
        val command=mutableListOf(File(bin,"libpython.so").path)
        if(!pythonCode)command.add(File(context.noBackupFilesDir,"youtubedl-android/yt-dlp/yt-dlp").path)
        if(!pythonCode)command.addAll(listOf("--no-cache-dir","--js-runtimes","quickjs:"+File(bin,"libqjs.so").path,"--ffmpeg-location",binary("ffmpeg")))
        command.addAll(arguments)
        val builder=ProcessBuilder(command).redirectErrorStream(true)
        val env=builder.environment()
        env.keys.filter{it.startsWith("PYTHON")}.toList().forEach{env.remove(it)}
        env["PYTHONHOME"]=runtime.path
        env["PYTHONNOUSERSITE"]="1"
        env["HOME"]=runtime.path
        env["TMPDIR"]=context.cacheDir.path
        env["SSL_CERT_FILE"]=File(runtime,"etc/tls/cert.pem").path
        env["LD_LIBRARY_PATH"]=File(runtime,"lib").path+":"+File(context.noBackupFilesDir,"youtubedl-android/packages/ffmpeg/usr/lib").path+":"+bin.path
        env["PATH"]=(System.getenv("PATH")?:"/system/bin")+":"+bin.path
        if(cancelled.get())throw IllegalStateException("Import cancelled")
        val child=builder.start();process=child
        val tail=StringBuilder()
        try {
            child.inputStream.bufferedReader().useLines{lines->lines.forEach{line->
                tail.append(line).append('\n');if(tail.length>16000)tail.delete(0,tail.length-12000)
                if(line.startsWith("[download]"))progress(line.take(160),5.0)
                if(cancelled.get())child.destroy()
            }}
            if(child.waitFor()!=0) {
                File(context.cacheDir,"last-download-error.txt").writeText(tail.toString())
                throw IllegalStateException(if(cancelled.get())"Import cancelled" else "Download failed: "+tail.lines().filter{it.isNotBlank()}.takeLast(3).joinToString(" ").take(450))
            }
            return tail.toString()
        }finally{child.destroy();process=null}
    }
    fun downloaderProbe():String {
        val config=downloaderProcess(listOf("-c","import sys,json,ssl,encodings; print(json.dumps({'paths':sys.path,'version':sys.version}))"),true)
        check(!config.contains("chaquopy")){"Downloader inherited chart-engine paths"}
        check(downloaderProcess(listOf("--version")).trim().isNotEmpty())
        return "Downloader starts independently of chart Python"
    }
    fun download(raw:String) {
        val array=JSONArray(raw)
        downloaderProcess((0 until array.length()).map{array.getString(it)})
    }
    @UsedByGodot fun generate(source:String,root:String,ai:Boolean) {submit(JSONObject().put("kind","link").put("source",source).put("library",root).put("ai",ai))}
    @UsedByGodot fun regenerate(folder:String,root:String,ai:Boolean) {submit(JSONObject().put("kind","regenerate").put("source",folder).put("library",root).put("ai",ai))}
    private fun submit(request:JSONObject,after:((Boolean)->Unit)?=null) {
        if(!busy.compareAndSet(false,true)){progress("An import is already running",0.0);return}
        cancelled.set(false);library=request.getString("library")
        activity?.runOnUiThread{context.startForegroundService(Intent(context,ImportService::class.java))}
        executor.execute {
            var ok=false
            try {initialize();progress("Preparing on-device importer…",1.0)
                val result=Python.getInstance().getModule("native_import").callAttr("run",request.toString(),this).toString()
                status=JSONObject(result).put("state","done").toString();ok=true
            }catch(e:Exception){fail(e)}finally{busy.set(false);context.stopService(Intent(context,ImportService::class.java));after?.invoke(ok)}
        }
    }
    @UsedByGodot fun import_cards(root:String) {
        library=root
        activity?.runOnUiThread {
            val intent=Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/png").addCategory(Intent.CATEGORY_OPENABLE)
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true)
            prefs.getString("last_import",null)?.let{intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI,Uri.parse(it))}
            activity?.startActivityForResult(intent,6101)
        }
    }
    @UsedByGodot fun export_card(folder:String,title:String,root:String) {
        val output=File(context.cacheDir,"export-card.png")
        submit(JSONObject().put("kind","card_export").put("source",folder).put("destination",output.path).put("library",root)){ok->
            if(ok)activity?.runOnUiThread {
                exportFile=output
                val intent=Intent(Intent.ACTION_CREATE_DOCUMENT).setType("image/png").addCategory(Intent.CATEGORY_OPENABLE)
                intent.putExtra(Intent.EXTRA_TITLE,title.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"),"_").take(100)+".png")
                prefs.getString("last_export",null)?.let{intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI,Uri.parse(it))}
                activity?.startActivityForResult(intent,6102)
            }else output.delete()
        }
    }
    override fun onMainActivityResult(requestCode:Int,resultCode:Int,data:Intent?) {
        if(requestCode==6102) {
            val file=exportFile;exportFile=null
            if(resultCode==Activity.RESULT_OK&&data?.data!=null&&file!=null){executor.execute {
                try {val uri=data.data!!;context.contentResolver.openOutputStream(uri,"wt")!!.use{out->file.inputStream().use{it.copyTo(out)}}
                    prefs.edit().putString("last_export",uri.toString()).apply();progress("Song card saved",100.0)
                }catch(e:Exception){fail(e)}finally{file.delete()}
            }}else file?.delete()
        }
        if(requestCode==6101&&resultCode==Activity.RESULT_OK&&data!=null){
            val uris=mutableListOf<Uri>();data.clipData?.let{for(i in 0 until it.itemCount)uris.add(it.getItemAt(i).uri)}?:data.data?.let{uris.add(it)}
            if(uris.isNotEmpty())prefs.edit().putString("last_import",uris.first().toString()).apply()
            if(uris.size>100){fail(IllegalArgumentException("Select up to 100 cards at a time"));return}
            if(busy.get()){progress("An import is already running",0.0);return}
            cancelled.set(false)
            executor.execute { importNext(uris,0,mutableListOf()) }
        }
    }
    private fun importNext(uris:List<Uri>,index:Int,failures:MutableList<String>) {
        if(index>=uris.size||cancelled.get()) {
            status=JSONObject().put("state","done").put("message","Imported ${index-failures.size}/${uris.size} cards"+(if(cancelled.get())"; cancelled" else "")+(if(failures.isNotEmpty())". "+failures.joinToString("; ").take(800) else "")).toString()
            return
        }
        val file=File(context.cacheDir,"import-card-$index.png")
        try {
            context.contentResolver.openInputStream(uris[index])!!.use{input->file.outputStream().use{out->
                val buffer=ByteArray(65536);var total=0
                while(true){val n=input.read(buffer);if(n<0)break;total+=n;require(total<=32*1024*1024){"Card exceeds 32 MB"};out.write(buffer,0,n)}
            }}
            submit(JSONObject().put("kind","card_import").put("source",file.path).put("library",library)) {ok->
                file.delete()
                if(!ok)failures.add("Card ${index+1}: "+JSONObject(status).optString("message","Failed"))
                importNext(uris,index+1,failures)
            }
        }catch(e:Exception){file.delete();failures.add("Card ${index+1}: "+(e.message?:"Cannot read card"));importNext(uris,index+1,failures)}
    }
}

class ImportService:Service() {
    override fun onBind(intent:Intent?) : IBinder? = null
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int {
        val manager=getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("imports","Song generation",NotificationManager.IMPORTANCE_LOW))
        startForeground(2401,Notification.Builder(this,"imports").setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Generating song on this device").setContentText("Return to the game for progress or to cancel.").setOngoing(true).build())
        return START_NOT_STICKY
    }
}
