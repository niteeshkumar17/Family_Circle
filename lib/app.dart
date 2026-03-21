import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'config/theme_config.dart';
import 'config/routes.dart';
import 'presentation/blocs/auth/auth_bloc.dart';
import 'presentation/blocs/family/family_bloc.dart';
import 'presentation/blocs/location/location_bloc.dart';

class FamilyNestApp extends StatelessWidget {
  const FamilyNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AuthBloc()),
        BlocProvider(create: (_) => FamilyBloc()),
        BlocProvider(create: (_) => LocationBloc()),
      ],
      child: MaterialApp(
        title: 'FamilyNest',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        initialRoute: AppRoutes.splash,
        onGenerateRoute: AppRoutes.generateRoute,
      ),
    );
  }
}
