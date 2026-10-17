import 'package:flutter/material.dart';
import 'package:vayora/app_state.dart';
import 'package:vayora/main.dart';
import 'package:vayora/theme.dart';
ThemeData captureTheme()=>buildTheme();
Widget paymentScreen(AppState state)=>Payments(state:state,showLatest:true);
