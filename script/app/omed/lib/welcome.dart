import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'dart:io';

import 'constants/colors.dart';

import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';

// =========================================
//       Service d'authentification
// =========================================
/// Regroupe les appels d'authentification Google et Supabase.
///
/// Les methodes renvoient la session creee, ou `null` lorsque le flux OAuth
/// desktop attend encore son retour par lien profond.
class AuthService {
  // Le client Google lit ses identifiants depuis l'environnement local.
  // Un secret livre dans une application cliente ne constitue pas un secret prive.
  final _googleSignIn = GoogleSignIn(
    params: GoogleSignInParams(
      clientId: dotenv.env['googleClientId'],
      clientSecret: dotenv.env['googleClientSecret'],
      redirectPort: 8000,
    ),
  );

  // Client Supabase initialise dans main.dart.
  final _supabase = Supabase.instance.client;

  // Protege le flux OAuth desktop contre les doubles clics pendant son ouverture.
  late bool _isOAuthInProgress = false;

  /// Authentifie via Google : jeton natif Android ou navigateur sur desktop.
  ///
  /// Android echange l'identifiant Google directement contre une session
  /// Supabase. Sur Linux, Windows et macOS, le navigateur revient via
  /// `omed://login-callback/`; l'etat de session est alors diffuse par Supabase.
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

  /// Cree un compte Supabase avec une adresse email et un mot de passe.
  ///
  /// Une session peut rester `null` si le projet exige une confirmation email.
  Future<Session?> signUpWithEmail(String email, String password) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );
    return response.session;
  }

  /// Ouvre une session Supabase avec les identifiants email/mot de passe.
  Future<Session?> signInWithEmail(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.session;
  }

  /// Ferme les sessions Google locales puis Supabase.
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _supabase.auth.signOut();
  }

  /// Indique si une session Supabase est presente.
  bool get isAuthenticated => _supabase.auth.currentSession != null;

  /// Utilisateur associe a la session courante, ou `null` si deconnecte.
  User? get currentUser => _supabase.auth.currentUser;
}

// =========================================
//       Page d'accueil / authentification
// =========================================
/// Ecran d'accueil qui ouvre les dialogues de connexion et d'inscription.
class Welcome extends StatefulWidget {
  const Welcome({super.key});

  @override
  State<Welcome> createState() => _WelcomeState();
}

/// Maintient les champs, validations et etats de chargement des formulaires.
class _WelcomeState extends State<Welcome> {
  /// Cree les controleurs des deux champs de saisie.
  @override
  void initState() {
    super.initState();

    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  /// Libere les controleurs et le notifier quand la page est retiree.
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _obscureText.dispose();
    super.dispose();
  }

  // Controleurs de formulaire, service d'authentification et etat des boutons.
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  final _auth = AuthService();
  bool _googleLoading = false;
  bool _emailLoading = false;
  final ValueNotifier<bool> _obscureText = ValueNotifier<bool>(true);
  final _formKey = GlobalKey<FormState>();

  /// Inverse l'affichage masque/visible du mot de passe dans les deux formulaires.
  void _toggleVisibility() {
    setState(() {
      _obscureText.value = !_obscureText.value;
    });
  }

  /// Lance Google Sign-In et affiche les erreurs de connexion a l'utilisateur.
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

  /// Valide un nouvel utilisateur et redirige si Supabase ouvre une session.
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

  /// Ouvre une session existante et rejoint l'accueil apres succes.
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

  // =========================================
  //       Dialogue de creation de compte
  // =========================================
  /// Construit la fenetre d'inscription email avec option Google.
  ///
  /// `Form` execute les validateurs avant l'envoi. La session reussie est
  /// traitee par [_signUpWithEmail]; une confirmation email peut la laisser nulle.
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
                  // =========================================
                  //             Champ adresse email
                  // =========================================
                  // Le validateur controle la presence et le format avant envoi.
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

                  // =========================================
                  //               Champ mot de passe
                  // =========================================
                  // Le notifier reconstruit seulement ce champ pour le bouton oeil.
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

            // =========================================
            //       Bouton valider l'inscription
            // =========================================
            // Cree le compte uniquement si tous les validateurs reussissent.
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

            // Separateur visuel entre la creation par email et Google.
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

            // =========================================
            //       Bouton connexion Google
            // =========================================
            // Le bouton est desactive pendant l'appel et montre un indicateur.
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

  // =========================================
  //       Dialogue de connexion existante
  // =========================================
  /// Construit le formulaire email de connexion et l'option Google.
  ///
  /// Les validateurs sont locaux; les erreurs d'identifiants renvoyees par
  /// Supabase sont ensuite presentees dans un SnackBar.
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
                  // =========================================
                  //             Champ adresse email
                  // =========================================
                  // L'adresse doit etre presente et respecter le format attendu.
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

                  // =========================================
                  //               Champ mot de passe
                  // =========================================
                  // L'icone permet de basculer entre texte masque et visible.
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

            // =========================================
            //        Bouton valider la connexion
            // =========================================
            // Tente la connexion seulement si les champs sont valides.
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

            // Separation entre les deux methodes d'authentification.
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

            // =========================================
            //       Bouton connexion Google
            // =========================================
            // Reutilise le meme flux Google que le bouton d'inscription.
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

  // =========================================
  //       Widget de la page d'accueil
  // =========================================
  /// Affiche la marque OMED et les actions de connexion, inscription et credits.
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
                    // Marque et avis indiquant que l'application est en beta.
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

                    // =========================================
                    //       Bouton connexion par email
                    // =========================================
                    // Ouvre la boite de dialogue du compte existant.
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

                    // =========================================
                    //       Bouton creation de compte
                    // =========================================
                    // Ouvre le formulaire d'inscription.
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

                    // =========================================
                    //              Bouton credits
                    // =========================================
                    // Action visuelle provisoire tant que la page credits n'existe pas.
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
