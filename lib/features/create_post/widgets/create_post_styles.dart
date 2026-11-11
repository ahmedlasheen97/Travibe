import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

const createPostTextStyle = TextStyle(
  fontFamily: 'Plus Jakarta Sans',
  fontSize: 16,
  height: 1.5,
  fontWeight: FontWeight.w400,
  color: DarkColors.whiteColor,
  decoration: TextDecoration.none,
  letterSpacing: 0,
);
const createPostSurface = Color(0xFF0A0A0A);

// Colors sampled from the Create Post Figma frames (docs/figma/home/).
const createPostAccent = Color(0xFFD4652D); // Post button
const createPostIconGrey = Color(0xFF989693); // "Add to your post" icons
const createPostChip = Color(0xFF2F2E2D); // Public pill, photo X buttons
const createPostDanger = DarkColors.dangerColor; // Discard
const createPostToast = Color(0xE62D2C2B); // Uploading toast
const createPostSuccess = Color(0xFF499851); // Published toast
