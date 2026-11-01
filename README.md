# Diagnostica ADB per Frameo 159K

Pacchetto microSD per verificare il percorso delle utility di manutenzione Frameo quando USB ADB, ADB Wi-Fi e la barra notifiche non sono accessibili.

La prima prova sulla cornice ha confermato esecuzione come UID 0, modello 159K, Rockchip RK3326, Android 8.1/API 27 e Frameo `v1.32.16_-_OTA_test (80321)`. La build Android è `RK3326_8.1_AY_FRAMEO_202511241509`; il fingerprint è `rockchip/rk3326_evb/rk3326_evb:8.1.0/OC/150829:user/release-keys`.

Il log rileva `ro.adb.secure=1`, adbd già avviato, porte TCP temporanea e persistente vuote e SELinux Permissive. Questi risultati descrivono questa unità; non dimostrano compatibilità di altre cornici.

## Cosa esegue il test

Il file di configurazione avvia il task di aggiornamento Frameo. Un APK locale privo di codice, con package `net.frameo.frame` e versionCode `80322`, permette di verificare un percorso di command injection documentato da altri proprietari. Il nome dell'APK contiene sintassi shell: deve essere copiato come file, mai incollato in un terminale.

Lo script eseguito legge identità del processo, modello, firmware, stato di adbd, posizione di `su` e modalità SELinux. Scrive esclusivamente `frameo-159k-probe.txt` e `frameo-159k-probe.done` sulla scheda. Non esegue `su`, non cambia impostazioni Android e non legge foto, password o chiavi. L'APK di prova ha una firma locale diversa da Frameo: un eventuale tentativo di aggiornamento viene rifiutato dalla verifica della firma Android. Un messaggio di aggiornamento fallito, da solo, non dimostra che lo script sia stato eseguito: serve il log.

Non è un installer di Termux. Prima si verifica il log, poi si valuta come ottenere accesso ADB autenticato sulla precisa unità.

## Primo accesso ADB autenticato

Il builder accetta anche la modalità `Adb`:

```powershell
./scripts/Build-SdProbe.ps1 -Mode Adb `
  -AdbPublicKey "$env:USERPROFILE/.android/adbkey.pub" `
  -Output ./outputs/frameo-159k-sd-adb
```

La chiave pubblica viene verificata sul PC e inserita con un commento neutro. La chiave privata non viene letta dal builder e non viene copiata sulla scheda. Il file `scripts/sd-enable-adb.sh` richiede UID 0 e verifica modello, piattaforma, API, build Android, fingerprint e autenticazione ADB prima di cambiare lo stato del dispositivo.

L'enabler salva sulla scheda il contenuto e i metadati delle precedenti autorizzazioni ADB, le porte originali e lo stato di adbd. Preserva le chiavi esistenti, aggiunge la chiave pubblica di questo PC, controlla i permessi, imposta soltanto `service.adb.tcp.port=5555` e riavvia adbd. Verifica il listener e mantiene `ro.adb.secure=1`; `persist.adb.tcp.port` resta al valore originale. Questa prima configurazione non garantisce accesso dopo un riavvio della cornice.

In caso di errore, tenta di ripristinare chiavi, metadati, porta temporanea e stato del daemon. Il risultato del ripristino è registrato senza dichiarare successo quando una verifica fallisce. Le copie di stato nella cartella `frameo-159k-adb` vanno conservate localmente fino alla verifica della connessione. Il marker `started` impedisce tentativi ripetuti dopo un'interruzione; non va eliminato per aggirare un errore senza prima controllare il log e lo stato del dispositivo.

L'archivio contiene una nuova struttura di scheda: trasferire i file con il trigger `Frameo_utilities/frameo_utilities.config` per ultimo. Non sovrascrivere pacchetti di manutenzione altrui o baseline di tentativi precedenti. Il trasferimento fatto per questa unità controlla prima gli hash del precedente pacchetto diagnostico e ne conserva una copia locale. Dopo la prova, il PC deve verificare `adb connect` e l'esecuzione di una shell autenticata. Il messaggio dell'utility `APK successfully installed` non costituisce questa verifica.

Il sorgente e il pacchetto sono verificati sul PC. L'esecuzione dell'enabler ADB su hardware resta da verificare.

## Verifiche del codice ADB

```sh
bash tests/test-adb-enabler.sh
```

I test eseguono la logica shell su copie isolate sotto `work/`. Solo nelle copie di test i percorsi Android vengono sostituiti con percorsi di lavoro; proprietà, daemon, listener e metadati Unix sono simulati. Vengono verificati conservazione delle chiavi, baseline assente o vuota, mancata corrispondenza del firmware, esecuzione singola e ripristino dopo errori di listener, proprietà o permessi, anche con adbd inizialmente spento. Non sono prove hardware né verifiche del driver USB o della rete reale.

## Costruzione

Occorrono PowerShell 7, JDK 17, build-tools Android ufficiali per Windows e un `android.jar` ufficiale. Gli strumenti scaricati vengono conservati in `work/` e non sono versionati.

```powershell
./scripts/Build-SdProbe.ps1 `
  -BuildTools ./work/android-tools/build-tools_r36_windows/android-16 `
  -AndroidJar ./work/android-tools/platform-27_r03/android-8.1.0/android.jar
```

Il builder crea un APK senza DEX, verifica firma e identità, prepara la struttura della scheda e produce un archivio ZIP con un manifest SHA256. I file di firma restano in `work/` e non sono inclusi nel pacchetto.

## Prova sulla cornice

1. Estrai il contenuto dell'archivio nella cartella principale di una microSD già riconosciuta dalla cornice. La cartella `Frameo_utilities` e il file `p_frameo_jb` devono essere direttamente nella cartella principale, senza una cartella aggiuntiva intermedia. Conserva esattamente tutti i nomi.
2. Con Frameo avviato, apri Impostazioni e inserisci la scheda. Il test può avviarsi automaticamente.
3. Attendi 20–30 secondi. Se compare un task, annota il messaggio e chiudilo quando terminato.
4. Rimuovi la scheda in sicurezza e leggila sul PC. Il risultato utile è `frameo-159k-probe.txt`.
5. Rimuovi i file del pacchetto dalla scheda dopo la prova per evitare nuovi avvii del task. Per ripetere deliberatamente il test, conserva il vecchio log e rimuovi il suo marker `.done`.

Se non compare il log, il test non ha dimostrato compatibilità. Non modificare immagini boot, loader o firmware sulla base di queste istruzioni.

## Fonti e limiti

- [Segnalazioni 159K, incluso Frameo 80321](https://github.com/wesbos/photo-frame-dashboard/issues/126).
- [Descrizione del percorso SD sul 159K con Frameo 1.30.19](https://github.com/dusty-du/frameo-159k-jailbreak-builder).
- [Test diagnostico dello stesso meccanismo su un Dromart MI86 con Frameo 80321](https://github.com/wesbos/photo-frame-dashboard/pull/262). Il firmware Android e l'hardware di quel dispositivo sono diversi: il suo enabler ADB non viene utilizzato.

La riuscita su altre unità non garantisce la riuscita su questa cornice. Distinguere il test diagnostico già riuscito sulla cornice, le simulazioni sul PC e la verifica ADB reale ancora necessaria.
