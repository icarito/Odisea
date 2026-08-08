package com.godot.game;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;

import java.io.File;
import java.util.Arrays;
import java.util.List;

/** Opens a verified APK downloaded under user://updates through a content URI. */
public class OdiseaUpdater extends GodotPlugin {
	private static OdiseaUpdater instance;
	private String pendingApkPath = "";

	public OdiseaUpdater(Godot godot) {
		super(godot);
		instance = this;
	}

	@NonNull
	@Override
	public String getPluginName() {
		return "OdiseaUpdater";
	}

	@NonNull
	@Override
	public List<String> getPluginMethods() {
		return Arrays.asList("install_apk", "can_install_packages");
	}

	public boolean can_install_packages() {
		Activity activity = getActivity();
		return activity != null && (Build.VERSION.SDK_INT < Build.VERSION_CODES.O
				|| activity.getPackageManager().canRequestPackageInstalls());
	}

	public boolean install_apk(String absolutePath) {
		pendingApkPath = absolutePath == null ? "" : absolutePath;
		if (pendingApkPath.isEmpty()) {
			return false;
		}
		if (!can_install_packages()) {
			Activity activity = getActivity();
			if (activity == null) {
				return false;
			}
			try {
				Intent settings = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
						Uri.parse("package:" + activity.getPackageName()));
				activity.startActivity(settings);
				return true;
			} catch (RuntimeException exception) {
				return false;
			}
		}
		return launchPendingInstaller();
	}

	private boolean launchPendingInstaller() {
		Activity activity = getActivity();
		File apk = new File(pendingApkPath);
		if (activity == null || !apk.isFile()) {
			return false;
		}
		try {
			Uri uri = FileProvider.getUriForFile(activity,
					activity.getPackageName() + ".updateprovider", apk);
			Intent intent = new Intent(Intent.ACTION_VIEW);
			intent.setDataAndType(uri, "application/vnd.android.package-archive");
			intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
			activity.startActivity(intent);
			pendingApkPath = "";
			return true;
		} catch (RuntimeException exception) {
			return false;
		}
	}

	/** Called after returning from Android's "install unknown apps" settings. */
	public static void onHostResume() {
		if (instance != null && !instance.pendingApkPath.isEmpty() && instance.can_install_packages()) {
			instance.launchPendingInstaller();
		}
	}
}
