//Flixel
import flixel.sound.FlxSound;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup.FlxTypedGroup;

import funkin.backend.utils.CoolUtil;
import funkin.backend.utils.TranslationUtil as TU;

import lime.utils.AssetLibrary;
import openfl.utils.Assets as OpenFlAssets;
import animate.FlxAnimateFrames;
import lime.utils.Assets;

#if sys
import sys.FileSystem;
#end
import sys.io.File;
import haxe.io.Path;