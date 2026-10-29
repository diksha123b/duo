import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

const isWeb = true;

Widget renderWebButton() => SizedBox(height: 52, child: web.renderButton());
