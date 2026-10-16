import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'dart:io';

import 'constants/colors.dart';

import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class AuthService {

  final _googleSignIn = GoogleSignIn(
    params: GoogleSignInParams(
      clientId: dotenv.env['googleClientId'],
      clientSecret: dotenv.env['googleClientSecret'],
      redirectPort: 8000,
    ),
  );

  final _supabase = Supabase.instance.client;

  late bool _isOAuthInProgress = false;

  Future<Session?> signInWithGoogle() async {
    if (Platform.isAndroid) {
      final credentials = await _googleSignIn.signIn();

      if (credentials == null) {
        print('GOOGLE : credentials == null');
        return null;
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: credentials.idToken!,
        accessToken: credentials.accessToken,
      );

      return response.session;
    }

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      if (_isOAuthInProgress) return null;
      _isOAuthInProgress = true;

      try {
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'omed://login-callback/',
          authScreenLaunchMode: LaunchMode.externalApplication,
        );
      } finally {
        // Empêche les clics répétés pendant le lancement.
        // La session sera traitée par onAuthStateChange.
        Future.delayed(
          const Duration(seconds: 30),
          () => _isOAuthInProgress = false,
        );
      }

      return null;
    }

    return null;
  }

  Future<Session?> signUpWithEmail(String email, String password) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );
    return response.session;
  }

  Future<Session?> signInWithEmail(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.session;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _supabase.auth.signOut();
  }

  bool get isAuthenticated => _supabase.auth.currentSession != null;

  User? get currentUser => _supabase.auth.currentUser;
}

class Welcome extends StatefulWidget {
  const Welcome({super.key});

  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  @override
  void initState() {
    super.initState();

    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _obscureText.dispose();
    super.dispose();
  }

  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  final _auth = AuthService();
  bool _googleLoading = false;
  bool _emailLoading = false;
  final ValueNotifier<bool> _obscureText = ValueNotifier<bool>(true);
  final _formKey = GlobalKey<FormState>();

  void _toggleVisibility() {
    setState(() {
      _obscureText.value = !_obscureText.value;
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      final session = await _auth.signInWithGoogle();
      if (session != null && mounted) {
        Navigator.of(context).pop();

        Navigator.pushReplacementNamed(context, '/home');
      } else if (Platform.isLinux && mounted) {
        Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: ${e.message}')));
        print('Erreur: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
        print('Erreur: $e');
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _signUpWithEmail(String email, String password) async {
    setState(() => _emailLoading = true);
    try {
      final session = await _auth.signUpWithEmail(email, password);
      if (session != null && mounted) {
        Navigator.of(context).pop();
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: ${e.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  Future<void> _signInWithEmail(String email, String password) async {
    setState(() => _emailLoading = true);
    try {
      final session = await _auth.signInWithEmail(email, password);
      if (session != null && mounted) {
        Navigator.of(context).pop();
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: ${e.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  Widget _signupPupopDialog(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.secondarySurface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.1,
        vertical: MediaQuery.of(context).size.height * 0.1,
      ),
      contentPadding: EdgeInsets.all(24),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Se connecter",
              style: TextStyle(color: AppColors.textPrimary, fontSize: 24),
            ),
            SizedBox(height: 32),
            Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: AppColors.primarySurface),
                    cursorColor: AppColors.primarySurface,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Email requis";
                      }
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$')
                          .hasMatch(value)) {
                        return "Email invalide";
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: TextStyle(
                        color: const Color.fromARGB(255, 68, 68, 68),
                      ),
                      border: WidgetStateInputBorder.resolveWith((states) {
                        if (states.contains(WidgetState.focused)) {
                          return OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primarySurface,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          );
                        }
                        if (states.contains(WidgetState.hovered)) {
                          return OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.textSecondary,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          );
                        }
                        return OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                          borderRadius: BorderRadius.circular(5),
                        );
                      }),
                    ),
                  ),
                  SizedBox(height: 32),

                  ValueListenableBuilder<bool>(
                    valueListenable: _obscureText,
                    builder: (context, obscure, _) {
                      return TextFormField(
                        controller: _passwordController,
                        obscureText: obscure,
                        style: TextStyle(color: AppColors.textPrimary),
                        cursorColor: AppColors.primarySurface,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Mot de passe requis";
                          }
                          if (value.length < 6) {
                            return "Minimum 6 caractères";
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          labelStyle: TextStyle(
                            color: const Color.fromARGB(255, 68, 68, 68),
                          ),
                          border: WidgetStateInputBorder.resolveWith((states) {
                            if (states.contains(WidgetState.focused)) {
                              return OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primarySurface,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              );
                            }
                            if (states.contains(WidgetState.hovered)) {
                              return OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.textSecondary,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              );
                            }
                            return OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey),
                              borderRadius: BorderRadius.circular(5),
                            );
                          }),
                          suffixIcon: IconButton(
                            onPressed: _toggleVisibility,
                            icon: Icon(
                              obscure ? Icons.visibility_off : Icons.visibility,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 32),

            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  _signUpWithEmail(
                    _emailController.text,
                    _passwordController.text,
                  );
                }
              },
              child: Text(
                'Valider',
                style: TextStyle(color: AppColors.background),
              ),
            ),

            SizedBox(height: 32),
            Row(
              children: [
                Expanded(child: Divider(thickness: 1)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text("OU", style: TextStyle(color: Colors.grey)),
                ),
                Expanded(child: Divider(thickness: 1)),
              ],
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              icon: FaIcon(
                FontAwesomeIcons.google,
                color: AppColors.background,
              ),
              label: _googleLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      "Continuer avec google",
                      style: TextStyle(color: AppColors.background),
                    ),
              onPressed: _googleLoading ? null : _signInWithGoogle,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primarySurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signinPupopDialog(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.secondarySurface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.1,
        vertical: MediaQuery.of(context).size.height * 0.1,
      ),
      contentPadding: EdgeInsets.all(24),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Se connecter",
              style: TextStyle(color: AppColors.textPrimary, fontSize: 24),
            ),
            SizedBox(height: 32),
            Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: AppColors.primarySurface),
                    cursorColor: AppColors.primarySurface,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Email requis";
                      }
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$')
                          .hasMatch(value)) {
                        return "Email invalide";
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: TextStyle(
                        color: const Color.fromARGB(255, 68, 68, 68),
                      ),
                      border: WidgetStateInputBorder.resolveWith((states) {
                        if (states.contains(WidgetState.focused)) {
                          return OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primarySurface,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          );
                        }
                        if (states.contains(WidgetState.hovered)) {
                          return OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.textSecondary,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          );
                        }
                        return OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                          borderRadius: BorderRadius.circular(5),
                        );
                      }),
                    ),
                  ),
                  SizedBox(height: 32),

                  ValueListenableBuilder<bool>(
                    valueListenable: _obscureText,
                    builder: (context, obscure, _) {
                      return TextFormField(
                        controller: _passwordController,
                        obscureText: obscure,
                        style: TextStyle(color: AppColors.textPrimary),
                        cursorColor: AppColors.primarySurface,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Mot de passe requis";
                          }
                          if (value.length < 6) {
                            return "Minimum 6 caractères";
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          labelStyle: TextStyle(
                            color: const Color.fromARGB(255, 68, 68, 68),
                          ),
                          border: WidgetStateInputBorder.resolveWith((states) {
                            if (states.contains(WidgetState.focused)) {
                              return OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primarySurface,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              );
                            }
                            if (states.contains(WidgetState.hovered)) {
                              return OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.textSecondary,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              );
                            }
                            return OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey),
                              borderRadius: BorderRadius.circular(5),
                            );
                          }),
                          suffixIcon: IconButton(
                            onPressed: _toggleVisibility,
                            icon: Icon(
                              obscure ? Icons.visibility_off : Icons.visibility,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 32),

            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  _signInWithEmail(
                    _emailController.text,
                    _passwordController.text,
                  );
                }
              },
              child: Text(
                'Valider',
                style: TextStyle(color: AppColors.background),
              ),
            ),
            SizedBox(height: 32),
            Row(
              children: [
                Expanded(child: Divider(thickness: 1)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text("OU", style: TextStyle(color: Colors.grey)),
                ),
                Expanded(child: Divider(thickness: 1)),
              ],
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              icon: FaIcon(
                FontAwesomeIcons.google,
                color: AppColors.background,
              ),
              label: _googleLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      "Continuer avec google",
                      style: TextStyle(color: AppColors.background),
                    ),
              onPressed: _googleLoading ? null : _signInWithGoogle,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primarySurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          final circleSize = width * 0.3 * 3.25;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -(circleSize) / 2,
                top: height * 0,
                width: circleSize,
                height: circleSize,
                child: Image(
                  image: AssetImage('lib/assets/bg-circle-glow.png'),
                  fit: BoxFit.fill,
                ),
              ),

              Positioned(
                top: height * 0.7,
                right: -(circleSize) / 1.5,
                child: Image(
                  image: AssetImage('lib/assets/bg-circle-glow.png'),
                ),
              ),
              Center(
                child: Column(
                  children: [
                    SizedBox(height: height * 0.2),
                    Text(
                      "OMED",
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 60,
                      ),
                    ),
                    Text(
                      "Omed est en version bêta, ",
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      "merci de signaler les bugs potentiels",
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                    SizedBox(height: height * 0.3),

                    //====================
                    // LOGIN BUTTON
                    //====================
                    SizedBox(
                      height: height * 0.07,
                      width: width * 0.75,
                      child: ElevatedButton(
                        onPressed: () => {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) =>
                                _signinPupopDialog(context),
                          ),
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.secondarySurface,
                        ),
                        child: Text(
                          "Connexion",
                          style: TextStyle(color: AppColors.primarySurface),
                        ),
                      ),
                    ),

                    SizedBox(height: height * 0.02),

                    //====================
                    // SIGNUP BUTTON
                    //====================
                    SizedBox(
                      height: height * 0.07,
                      width: width * 0.75,
                      child: ElevatedButton(
                        onPressed: () => {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) =>
                                _signupPupopDialog(context),
                          ),
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primarySurface,
                        ),
                        child: Text(
                          "Créer un compte",
                          style: TextStyle(color: AppColors.secondarySurface),
                        ),
                      ),
                    ),

                    SizedBox(height: height * 0.02),

                    //====================
                    // CREDITS BUTTON
                    //====================
                    SizedBox(
                      height: height * 0.07,
                      width: width * 0.75,
                      child: ElevatedButton(
                        onPressed: () => {print("Credits")},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.transparent,
                          elevation: 0,
                          overlayColor: Colors.transparent,
                          splashFactory: NoSplash.splashFactory,
                        ),
                        child: Text(
                          "Crédits",
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                            decoration: TextDecoration.underline,
                            decorationThickness: 1,
                            decorationColor: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
