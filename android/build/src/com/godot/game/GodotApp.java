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

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

/**
 * Template activity for Godot Android custom builds.
 * Feel free to extend and modify this class for your custom logic.
 */
public class GodotApp extends FullScreenGodotApp {
	// Buffer for a deep link that arrived before the OdiseaDeepLink plugin was
	// constructed (the normal launch ordering). The plugin drains this in its
	// constructor; onNewIntent (app already running) feeds the plugin directly.
	private static String sPendingDeepLink = "";

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
		// The launch Intent arrives before the engine constructs the
		// OdiseaDeepLink plugin, so stash the odisea:// URI for it to pick up.
		stashDeepLink(getIntent());
	}

	@Override
	public void onNewIntent(Intent intent) {
		super.onNewIntent(intent);
		// singleInstancePerTask: re-launches while running come through here.
		setIntent(intent);
		stashDeepLink(intent);
		OdiseaDeepLink.feedIntent(intent);
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
