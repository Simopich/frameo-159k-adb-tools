# Diagnostica ADB per Frameo 159K

Pacchetto microSD per verificare il percorso delle utility di manutenzione Frameo quando USB ADB, ADB Wi-Fi e la barra notifiche non sono accessibili.

La cornice di destinazione dichiara modello 159K e Frameo `v1.32.16_-_OTA_test (80321)`. La compatibilità hardware non è ancora verificata.

## Cosa esegue il test

Il file di configurazione avvia il task di aggiornamento Frameo. Un APK locale privo di codice, con package `net.frameo.frame` e versionCode `80322`, permette di verificare un percorso di command injection documentato da altri proprietari. Il nome dell'APK contiene sintassi shell: deve essere copiato come file, mai incollato in un terminale.

Lo script eseguito legge identità del processo, modello, firmware, stato di adbd, posizione di `su` e modalità SELinux. Scrive esclusivamente `frameo-159k-probe.txt` e `frameo-159k-probe.done` sulla scheda. Non esegue `su`, non cambia impostazioni Android e non legge foto, password o chiavi. L'APK di prova ha una firma locale diversa da Frameo: un eventuale tentativo di aggiornamento viene rifiutato dalla verifica della firma Android. Un messaggio di aggiornamento fallito, da solo, non dimostra che lo script sia stato eseguito: serve il log.

Non è un installer di Termux. Prima si verifica il log, poi si valuta come ottenere accesso ADB autenticato sulla precisa unità.

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

La riuscita su altre unità non garantisce la riuscita su questa cornice. La preparazione del pacchetto e le verifiche sul PC non costituiscono una prova sul dispositivo.
