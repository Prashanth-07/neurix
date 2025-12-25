import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await authService.registerWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (result.success) {
        // Registration successful - pop back to login, AuthWrapper will handle navigation
        if (mounted) {
          Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
        elevation: 0,
      ),
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
                    Icons.person_add_outlined,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSizes.paddingMedium),
                  Text(
                    'Create Account',
                    style: AppTextStyles.heading,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSizes.paddingSmall),
                  Text(
                    'Sign up to get started',
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
                    textInputAction: TextInputAction.next,
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
                  ),
                  const SizedBox(height: AppSizes.paddingMedium),

                  // Confirm Password Field
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    enabled: !_isLoading,
                    decoration: AppInputDecorations.textField(
                      label: 'Confirm Password',
                      icon: Icons.lock_outline,
                      hintText: 'Confirm your password',
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.textLight,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _register(),
                  ),
                  const SizedBox(height: AppSizes.paddingLarge),

                  // Register Button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _register,
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
                        : const Text('Create Account'),
                  ),
                  const SizedBox(height: AppSizes.paddingMedium),

                  // Terms and Privacy Policy
                  Text(
                    'By creating an account, you agree to our Terms of Service and Privacy Policy',
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
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