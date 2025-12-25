import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (result.success) {
        // Login successful - AuthWrapper will handle navigation automatically
        // Just stop the loading indicator
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = result.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await authService.signInWithGoogle();

      if (!mounted) return;

      if (result.success) {
        // Google Sign-In successful - AuthWrapper will handle navigation automatically
        // Just stop the loading indicator
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = result.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
        _isLoading = false;
      });
    }
  }

  void _navigateToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.paddingLarge),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Logo or Title
                  const Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSizes.paddingMedium),
                  Text(
                    'Welcome Back',
                    style: AppTextStyles.heading,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSizes.paddingSmall),
                  Text(
                    'Sign in to continue',
                    style: AppTextStyles.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSizes.paddingLarge),

                  // Error Message
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSizes.paddingMedium),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSizes.paddingMedium),
                  ],

                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    enabled: !_isLoading,
                    decoration: AppInputDecorations.textField(
                      label: 'Email',
                      icon: Icons.email_outlined,
                      hintText: 'Enter your email',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@') || !value.contains('.')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSizes.paddingMedium),

                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    enabled: !_isLoading,
                    decoration: AppInputDecorations.textField(
                      label: 'Password',
                      icon: Icons.lock_outline,
                      hintText: 'Enter your password',
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.textLight,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _signInWithEmail(),
                  ),
                  const SizedBox(height: AppSizes.paddingMedium),

                  // Sign In Button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _signInWithEmail,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSizes.paddingMedium,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Sign In'),
                  ),
                  const SizedBox(height: AppSizes.paddingMedium),

                  // OR Divider
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.paddingMedium,
                        ),
                        child: Text(
                          'OR',
                          style: AppTextStyles.caption,
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: AppSizes.paddingMedium),

                  // Google Sign In Button
                  _GoogleSignInButton(onPressed: _isLoading ? null : _signInWithGoogle),
                  const SizedBox(height: AppSizes.paddingLarge),

                  // Register Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Don\'t have an account? ',
                        style: AppTextStyles.caption,
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : _navigateToRegister,
                        child: const Text('Register'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _GoogleSignInButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(12),
        side: const BorderSide(color: Colors.grey),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.g_mobiledata, color: Colors.red[700], size: 24),
          const SizedBox(width: 12),
          const Text(
            'Sign in with Google',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
} 