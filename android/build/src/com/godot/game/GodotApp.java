/**************************************************************************/
/*  GodotApp.java                                                         */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

package com.godot.game;

import org.godotengine.godot.FullScreenGodotApp;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Display;
import android.view.WindowManager;

/**
 * Template activity for Godot Android custom builds.
 * Feel free to extend and modify this class for your custom logic.
 */
public class GodotApp extends FullScreenGodotApp {
	// Buffer for a deep link that arrived before the OdiseaDeepLink plugin was
	// constructed (the normal launch ordering). The plugin drains this in its
	// constructor; onNewIntent (app already running) feeds the plugin directly.
	private static String sPendingDeepLink = "";

	// Brightness floor for the game window while gameplay is active. Long scene
	// loads (menu -> dome) left the screen untouched long enough for power
	// management to dim it, even with the engine's keep-screen-on flag
	// (battery-saver / adaptive dimming ignore FLAG_KEEP_SCREEN_ON on some OEMs).
	// PauseManager (via the OdiseaDisplay plugin) drops this on pause.
	private static final float BRIGHTNESS_FLOOR = 0.6f;

	// On 90/120 Hz panels, rendering at the panel's full refresh only adds heat
	// and thermal throttling (the engine has no frame-rate cap on Android):
	// pin the display mode closest to this refresh rate. No-op on 60 Hz panels.
	private static final float TARGET_REFRESH_HZ = 60.0f;

	/** Drained by OdiseaDeepLink's constructor for the launch Intent. */
	public static String takePendingDeepLink() {
		String link = sPendingDeepLink;
		sPendingDeepLink = "";
		return link;
	}

	@Override
	public void onCreate(Bundle savedInstanceState) {
		setTheme(R.style.GodotAppMainTheme);
		super.onCreate(savedInstanceState);
		keepScreenAwakeAndBright();
		pinDisplayRefreshRate();
		// The launch Intent arrives before the engine constructs the
		// OdiseaDeepLink plugin, so stash the odisea:// URI for it to pick up.
		stashDeepLink(getIntent());
	}

	/**
	 * Initial safe state at boot: the app starts on the menu/scene before any
	 * GDScript runs, so keep the screen on. From then on PauseManager owns the
	 * gameplay/pause transitions through the OdiseaDisplay plugin.
	 */
	private void keepScreenAwakeAndBright() {
		applyGameplayDisplayState(this, true);
	}

	/**
	 * Shared gameplay/pause screen power policy. Called by GodotApp for the boot
	 * state and by the OdiseaDisplay plugin for every PauseManager transition.
	 *
	 * active = true keeps the screen on and pins a brightness floor (never below
	 * the user's setting); active = false drops both so the system can dim/sleep
	 * while paused.
	 */
	static void applyGameplayDisplayState(Activity activity, boolean active) {
		if (activity == null || activity.getWindow() == null) {
			return;
		}
		WindowManager.LayoutParams layoutParams = activity.getWindow().getAttributes();
		if (active) {
			activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
			int systemBrightness = Settings.System.getInt(
					activity.getContentResolver(), Settings.System.SCREEN_BRIGHTNESS, 128);
			layoutParams.screenBrightness = Math.max(systemBrightness / 255.0f, BRIGHTNESS_FLOOR);
		} else {
			activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
			// -1 = BRIGHTNESS_OVERRIDE_NONE: follow the system brightness.
			layoutParams.screenBrightness = -1.0f;
		}
		activity.getWindow().setAttributes(layoutParams);
	}

	/**
	 * Pins the display to the mode closest to TARGET_REFRESH_HZ with the same
	 * resolution as the default mode. preferredDisplayModeId needs API 23;
	 * below that (or on panels without higher-rate modes) it is a no-op.
	 */
	private void pinDisplayRefreshRate() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
			return;
		}
		Display display = getWindowManager().getDefaultDisplay();
		Display.Mode current = display.getMode();
		Display.Mode best = current;
		float bestDelta = Float.MAX_VALUE;
		for (Display.Mode mode : display.getSupportedModes()) {
			if (mode.getPhysicalWidth() != current.getPhysicalWidth()
					|| mode.getPhysicalHeight() != current.getPhysicalHeight()) {
				continue;
			}
			float delta = Math.abs(mode.getRefreshRate() - TARGET_REFRESH_HZ);
			if (delta < bestDelta) {
				bestDelta = delta;
				best = mode;
			}
		}
		if (best.getModeId() != current.getModeId()) {
			WindowManager.LayoutParams layoutParams = getWindow().getAttributes();
			layoutParams.preferredDisplayModeId = best.getModeId();
			getWindow().setAttributes(layoutParams);
		}
	}

	@Override
	public void onNewIntent(Intent intent) {
		super.onNewIntent(intent);
		// singleInstancePerTask: re-launches while running come through here.
		setIntent(intent);
		stashDeepLink(intent);
		OdiseaDeepLink.feedIntent(intent);
	}

	@Override
	protected void onResume() {
		super.onResume();
		OdiseaUpdater.onHostResume();
	}

	private void stashDeepLink(Intent intent) {
		if (intent == null) {
			return;
		}
		Uri data = intent.getData();
		if (data != null && "odisea".equals(data.getScheme())) {
			// Buffer for the plugin constructor; also feed it live in case the
			// plugin already exists (onNewIntent path).
			sPendingDeepLink = data.toString();
			OdiseaDeepLink.feedLink(data.toString());
		}
	}
}
