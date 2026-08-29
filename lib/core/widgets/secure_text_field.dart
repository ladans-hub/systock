import 'package:flutter/material.dart';

class SecureTextField extends StatefulWidget {
  const SecureTextField({
    required this.controller,
    required this.decoration,
    this.autofocus = false,
    this.keyboardType = TextInputType.visiblePassword,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final bool autofocus;
  final TextInputType keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SecureTextField> createState() => _SecureTextFieldState();
}

class _SecureTextFieldState extends State<SecureTextField> {
  bool hidden = true;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    autofocus: widget.autofocus,
    obscureText: hidden,
    keyboardType: widget.keyboardType,
    onSubmitted: widget.onSubmitted,
    decoration: widget.decoration.copyWith(
      suffixIcon: IconButton(
        onPressed: () => setState(() => hidden = !hidden),
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        tooltip: hidden ? 'Mostrar' : 'Ocultar',
      ),
    ),
  );
}
