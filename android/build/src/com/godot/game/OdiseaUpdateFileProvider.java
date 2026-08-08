package com.godot.game;

import androidx.core.content.FileProvider;

/** Distinct provider class so manifest merging keeps Godot's own FileProvider. */
public class OdiseaUpdateFileProvider extends FileProvider {
}
