import 'package:flutter/material.dart';

abstract final class MobiusTypography {
  static const sans = 'SF Pro Text';
  static const mono = 'SF Mono';

  static const display = TextStyle(
    fontFamily: sans,
    fontSize: 32,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: -0.4,
  );

  static const title = TextStyle(
    fontFamily: sans,
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  static const body = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  static const label = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  static const technical = TextStyle(
    fontFamily: mono,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const timestamp = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
}