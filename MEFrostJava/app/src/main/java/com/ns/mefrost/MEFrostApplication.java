package com.ns.mefrost;

import android.app.Application;
import android.content.Intent;
import android.util.Log;

import com.ns.matrix.MatrixService;
import com.ns.matrix.PCKManager;
import com.ns.matrixengine.IEngineSuperClient;
import com.ns.matrixengine.IEngineSuperClientListener;
import com.ns.sdkclient.ClientKeepAliveService;
import com.ns.sdkclient.EngineSuperClientGodot;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

public class MEFrostApplication extends Application {
    private static MEFrostApplication instance;
    private static final String TAG = "MEFrostApplication";
    private IEngineSuperClient engineSuperClient;
    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "MEFrostApplication created");
        instance = this;
        loadBundledNativeLibraries();
        initializePckWithSmartLoading();
        ClientKeepAliveService.start(this);
        initEngine();
    }

    private void loadBundledNativeLibraries() {
        String[] libraries = {"zmq", "MEFrost.android.template_release.arm64"};
        for (String library : libraries) {
            try {
                System.loadLibrary(library);
                Log.i(TAG, "Loaded native library " + library);
            } catch (UnsatisfiedLinkError error) {
                Log.w(TAG, "Native library load failed " + library, error);
            }
        }
    }

    // 从外部文件目录安装 PCK: assets/game.pck 会被复制成 files/game.obb 后按主包加载.
    private void initializePckWithSmartLoading() {
        File externalDir = getExternalFilesDir(null);
        if (externalDir == null) {
            throw new IllegalStateException("External files directory unavailable for bundled PCK");
        }
        String externalPath = new File(externalDir, "game.obb").getAbsolutePath();
        String installedPath = PCKManager.INSTANCE.smartInstallPckFromAssets(this, externalPath);
        if (installedPath == null || installedPath.isEmpty()) {
            throw new IllegalStateException("Bundled PCK installation returned no path");
        }
        try {
            File installedFile = new File(installedPath);
            byte[] bundledHash;
            byte[] installedHash;
            try (InputStream bundled = getAssets().open("game.pck");
                 InputStream installed = new FileInputStream(installedFile)) {
                bundledHash = sha256(bundled);
                installedHash = sha256(installed);
            }
            if (!MessageDigest.isEqual(bundledHash, installedHash)) {
                File temp = File.createTempFile("game-", ".pck", installedFile.getParentFile());
                try {
                    try (InputStream bundled = getAssets().open("game.pck")) {
                        Files.copy(bundled, temp.toPath(), StandardCopyOption.REPLACE_EXISTING);
                    }
                    byte[] copiedHash;
                    try (InputStream copied = new FileInputStream(temp)) {
                        copiedHash = sha256(copied);
                    }
                    if (!MessageDigest.isEqual(bundledHash, copiedHash)) {
                        throw new IOException("Bundled PCK copy failed verification");
                    }
                    Files.move(temp.toPath(), installedFile.toPath(),
                            StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
                    Log.i(TAG, "Replaced outdated PCK from bundled asset");
                } finally {
                    temp.delete();
                }
            }
        } catch (IOException | NoSuchAlgorithmException error) {
            throw new IllegalStateException("Unable to install bundled PCK", error);
        }
        Log.i(TAG, "PCK installed at " + installedPath);
    }

    private static byte[] sha256(InputStream input) throws IOException, NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] buffer = new byte[65536];
        int count;
        while ((count = input.read(buffer)) != -1) {
            digest.update(buffer, 0, count);
        }
        return digest.digest();
    }

    private void startMatrixServiceFromForeground() {
        try {
            Intent intent = new Intent(this, MatrixService.class);
            startForegroundService(intent);
            Log.i(TAG, "Requested MatrixService start");
        } catch (Exception e) {
            Log.w(TAG, "Failed to start MatrixService", e);
        }
    }

    public static MEFrostApplication getInstance() {
        return instance;
    }

    public IEngineSuperClient getEngineClient() {
        initEngine();
        return engineSuperClient;
    }
    public synchronized void initEngine() {
        if (engineSuperClient == null) {
            engineSuperClient = EngineSuperClientGodot.newBuilder(this)
                    .withServicePackageName(getPackageName())
                    .withServiceClassName(MatrixService.CLASS_NAME)
                    .withServiceConnectionId(1000001)
                    .withEngineClientListener(new IEngineSuperClientListener() {
                    @Override
                    public void onStarted(boolean b) {

                    }

                    @Override
                    public void onStopped() {
                        IEngineSuperClientListener.super.onStopped();
                    }

                    @Override
                    public void onPaused() {
                        IEngineSuperClientListener.super.onPaused();
                    }

                    @Override
                    public void onResume() {
                        IEngineSuperClientListener.super.onResume();
                    }

                    @Override
                    public void onSleep() {
                        IEngineSuperClientListener.super.onSleep();
                    }

                    @Override
                    public void onWakeup() {
                        IEngineSuperClientListener.super.onWakeup();
                    }

                    @Override
                    public void onBoundToService(boolean isSuccess) {
                    }
                    @Override
                    public void onUnboundToService() {
                        ensureEngineClientBound();
                    }
                })
                .build();
        }
        ensureEngineClientBound();
    }

    private void ensureEngineClientBound() {
        startMatrixServiceFromForeground();
        if (!engineSuperClient.isBoundToService()) {
            engineSuperClient.bindToService();
        }
    }
}
