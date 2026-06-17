/**************************************************************************/
/*  OdiseaDeepLink.java                                                    */
/**************************************************************************/
/* Minimal Godot 3.6 Android plugin exposing the launch/resume deep link  */
/* to GDScript. The dashboard opens odisea://replay?url=<signed> to play   */
/* a hotzone capture in the installed native build instead of the web      */
/* shell; Boot reads consume_deep_link() and routes to HotzonePlayer.      */
/**************************************************************************/

package com.godot.game;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;

import java.util.Collections;
import java.util.List;

/**
 * Singleton-style plugin. GodotApp feeds it the launch Intent (and any
 * onNewIntent while running); GDScript polls consume_deep_link() once at boot.
 *
 * The deep link is consume-once: reading it clears it, so a later scene change
 * or app resume doesn't replay a stale link.
 */
public class OdiseaDeepLink extends GodotPlugin {

	private static OdiseaDeepLink instance;

	// The most recent odisea:// URI handed to us, or null/empty if none pending.
	private String pendingLink = "";

	public OdiseaDeepLink(Godot godot) {
		super(godot);
		instance = this;
		// Pick up a deep link that GodotApp buffered before we existed (the
		// normal cold-launch ordering: Intent -> onCreate -> engine -> plugin).
		String buffered = GodotApp.takePendingDeepLink();
		if (buffered != null && buffered.startsWith("odisea://")) {
			pendingLink = buffered;
		}
	}

	@NonNull
	@Override
	public String getPluginName() {
		return "OdiseaDeepLink";
	}

	@NonNull
	@Override
	public List<String> getPluginMethods() {
		// Exposed to GDScript via Engine.get_singleton("OdiseaDeepLink").
		return Collections.singletonList("consume_deep_link");
	}

	/**
	 * Returns the pending odisea:// deep link and clears it (consume-once).
	 * Empty string when there is none.
	 */
	public String consume_deep_link() {
		String link = pendingLink == null ? "" : pendingLink;
		pendingLink = "";
		return link;
	}

	/** Called by GodotApp for the launch Intent and any onNewIntent. */
	public static void feedIntent(@Nullable Intent intent) {
		if (instance == null || intent == null) {
			return;
		}
		Uri data = intent.getData();
		if (data == null) {
			return;
		}
		String scheme = data.getScheme();
		if (scheme != null && scheme.equals("odisea")) {
			instance.pendingLink = data.toString();
		}
	}

	/**
	 * If GodotApp received an Intent before this plugin was constructed (the
	 * usual launch ordering), it can stash the URI string and replay it here.
	 */
	public static void feedLink(@Nullable String uri) {
		if (instance != null && uri != null && uri.startsWith("odisea://")) {
			instance.pendingLink = uri;
		}
	}
}
