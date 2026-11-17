import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/account_service.dart';
import '../utils/constants.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _signup = false;
  bool _obscure = true;

  @override void dispose() { _username.dispose(); _password.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final account = context.watch<AccountService>();
    return Scaffold(
      backgroundColor: JarvisColors.background,
      body: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: JarvisColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: JarvisColors.cyan.withOpacity(.3)),
              boxShadow: [BoxShadow(color: JarvisColors.cyan.withOpacity(.08),blurRadius:35)]),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.memory_rounded,color:JarvisColors.cyan,size:48),
              const SizedBox(height:14),
              const Text('JARVIS AI',textAlign:TextAlign.center,style:TextStyle(color:JarvisColors.textPrimary,fontSize:25,fontWeight:FontWeight.bold,letterSpacing:3)),
              const SizedBox(height:5),
              const Text('YOUR ASSISTANT. YOUR ACCOUNT. YOUR MEMORY.',textAlign:TextAlign.center,style:TextStyle(color:JarvisColors.textDim,fontSize:9,letterSpacing:1.2)),
              const SizedBox(height:30),
              Text(_signup ? 'Create your account' : 'Welcome back',style:const TextStyle(color:JarvisColors.textPrimary,fontSize:19,fontWeight:FontWeight.w600)),
              const SizedBox(height:16),
              TextField(controller:_username,autocorrect:false,enableSuggestions:false,
                style:const TextStyle(color:JarvisColors.textPrimary),
                decoration:const InputDecoration(labelText:'Username',prefixIcon:Icon(Icons.person_outline),helperText:'3–24 characters; letters, numbers, . _ -')),
              const SizedBox(height:12),
              TextField(controller:_password,obscureText:_obscure,
                style:const TextStyle(color:JarvisColors.textPrimary),
                decoration:InputDecoration(labelText:'Password',prefixIcon:const Icon(Icons.lock_outline),
                  suffixIcon:IconButton(onPressed:()=>setState(()=>_obscure=!_obscure),icon:Icon(_obscure?Icons.visibility:Icons.visibility_off)),
                  helperText:_signup?'At least 8 characters':''),
                onSubmitted:(_)=>_submit(account)),
              if (account.error != null) ...[
                const SizedBox(height:12),
                Text(account.error!,style:const TextStyle(color:JarvisColors.red,fontSize:12)),
              ],
              const SizedBox(height:20),
              SizedBox(height:50,child:ElevatedButton(
                onPressed:account.isBusy?null:()=>_submit(account),
                style:ElevatedButton.styleFrom(backgroundColor:JarvisColors.cyan,foregroundColor:JarvisColors.background),
                child:account.isBusy?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):Text(_signup?'CREATE ACCOUNT':'LOG IN',style:const TextStyle(fontWeight:FontWeight.bold,letterSpacing:2)),
              )),
              const SizedBox(height:12),
              TextButton(onPressed:account.isBusy?null:()=>setState(()=>_signup=!_signup),
                child:Text(_signup?'Already have an account? Log in':'New to JARVIS? Create an account',style:const TextStyle(color:JarvisColors.cyan))),
              const SizedBox(height:10),
              const Text('Your chats and memories sync securely to your account and follow you across devices.',textAlign:TextAlign.center,style:TextStyle(color:JarvisColors.textDim,fontSize:11,height:1.5)),
            ]),
          ),
        ),
      )),
    );
  }

  Future<void> _submit(AccountService account) async {
    FocusScope.of(context).unfocus();
    final u=_username.text.trim(), p=_password.text;
    final ok=_signup?await account.signUp(u,p):await account.login(u,p);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Welcome, ${account.username}.')));
    }
  }
}
