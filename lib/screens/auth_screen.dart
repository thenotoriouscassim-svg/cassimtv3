import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/account_service.dart';
import '../services/jarvis_service.dart';
import '../services/memory_service.dart';
import '../utils/constants.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _answer = TextEditingController();
  final _newPassword = TextEditingController();
  bool _signup = false, _forgot = false, _obscure = true, _questionLoaded = false;
  String _question = 'first_school';
  static const _questions = <String,String>{
    'first_school':'What was the name of your first school?',
    'childhood_friend':'What was the first name of your childhood best friend?',
    'first_pet':'What was the name of your first pet?',
    'birth_city':'In which city were you born?',
    'favourite_teacher':'What was the surname of a favourite teacher?',
  };

  @override void dispose() {
    _username.dispose(); _password.dispose(); _answer.dispose(); _newPassword.dispose(); super.dispose();
  }

  @override Widget build(BuildContext context) {
    final account = context.watch<AccountService>();
    return Scaffold(
      backgroundColor: JarvisColors.background,
      body: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: JarvisColors.surface, borderRadius: BorderRadius.circular(22),
              border: Border.all(color: JarvisColors.cyan.withOpacity(.3)),
              boxShadow: [BoxShadow(color: JarvisColors.cyan.withOpacity(.08),blurRadius:35)]),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.memory_rounded,color:JarvisColors.cyan,size:48),
              const SizedBox(height:14),
              const Text('JARVIS AI',textAlign:TextAlign.center,style:TextStyle(color:JarvisColors.textPrimary,fontSize:25,fontWeight:FontWeight.bold,letterSpacing:3)),
              const SizedBox(height:5),
              const Text('YOUR ASSISTANT. YOUR ACCOUNT. YOUR MEMORY.',textAlign:TextAlign.center,style:TextStyle(color:JarvisColors.textDim,fontSize:9,letterSpacing:1.2)),
              const SizedBox(height:30),
              Text(_forgot ? 'Reset your password' : (_signup ? 'Create your account' : 'Welcome back'),
                style:const TextStyle(color:JarvisColors.textPrimary,fontSize:19,fontWeight:FontWeight.w600)),
              const SizedBox(height:16),
              TextField(controller:_username,autocorrect:false,enableSuggestions:false,
                style:const TextStyle(color:JarvisColors.textPrimary),
                decoration:const InputDecoration(labelText:'Username',prefixIcon:Icon(Icons.person_outline),helperText:'3–24 characters; letters, numbers, . _ -')),
              if (!_forgot) ...[
                const SizedBox(height:12),
                TextField(controller:_password,obscureText:_obscure,style:const TextStyle(color:JarvisColors.textPrimary),
                  decoration:InputDecoration(labelText:'Password',prefixIcon:const Icon(Icons.lock_outline),
                    suffixIcon:IconButton(onPressed:()=>setState(()=>_obscure=!_obscure),icon:Icon(_obscure?Icons.visibility:Icons.visibility_off)),
                    helperText:_signup?'At least 8 characters':''), onSubmitted:(_)=>_submit(account)),
                if (_signup) ...[
                  const SizedBox(height:18),
                  const Text('Account recovery',style:TextStyle(color:JarvisColors.textPrimary,fontWeight:FontWeight.w600)),
                  const SizedBox(height:6),
                  const Text('Choose a question you will remember. You will need the answer if you ever forget your password.',
                    style:TextStyle(color:JarvisColors.textDim,fontSize:11,height:1.4)),
                  const SizedBox(height:10),
                  DropdownButtonFormField<String>(value:_question,isExpanded:true,dropdownColor:JarvisColors.surface,
                    style:const TextStyle(color:JarvisColors.textPrimary),decoration:const InputDecoration(labelText:'Recovery question'),
                    items:_questions.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value,overflow:TextOverflow.ellipsis))).toList(),
                    onChanged:(v){if(v!=null)setState(()=>_question=v);}),
                  const SizedBox(height:12),
                  TextField(controller:_answer,autocorrect:false,enableSuggestions:false,
                    style:const TextStyle(color:JarvisColors.textPrimary),
                    decoration:const InputDecoration(labelText:'Your recovery answer',prefixIcon:Icon(Icons.security_outlined))),
                ],
              ] else ...[
                if (!_questionLoaded) ...[
                  const SizedBox(height:16),
                  const Text('Enter your username to retrieve your recovery question.',style:TextStyle(color:JarvisColors.textDim,fontSize:12)),
                ] else ...[
                  const SizedBox(height:16),
                  Text(account.recoveryQuestion ?? '',style:const TextStyle(color:JarvisColors.cyan,fontWeight:FontWeight.w600)),
                  const SizedBox(height:10),
                  TextField(controller:_answer,autocorrect:false,enableSuggestions:false,
                    style:const TextStyle(color:JarvisColors.textPrimary),
                    decoration:const InputDecoration(labelText:'Recovery answer',prefixIcon:Icon(Icons.security_outlined))),
                  const SizedBox(height:12),
                  TextField(controller:_newPassword,obscureText:true,style:const TextStyle(color:JarvisColors.textPrimary),
                    decoration:const InputDecoration(labelText:'New password',prefixIcon:Icon(Icons.lock_reset),helperText:'At least 8 characters')),
                ],
              ],
              if (account.error != null) ...[
                const SizedBox(height:12),
                Text(account.error!,style:const TextStyle(color:JarvisColors.red,fontSize:12)),
              ],
              const SizedBox(height:20),
              SizedBox(height:50,child:ElevatedButton(
                onPressed:account.isBusy?null:()=>_submit(account),
                style:ElevatedButton.styleFrom(backgroundColor:JarvisColors.cyan,foregroundColor:JarvisColors.background),
                child:account.isBusy?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):
                  Text(_forgot?(_questionLoaded?'RESET PASSWORD':'GET RECOVERY QUESTION'):(_signup?'CREATE ACCOUNT':'LOG IN'),
                    style:const TextStyle(fontWeight:FontWeight.bold,letterSpacing:2)),
              )),
              const SizedBox(height:12),
              if (!_signup && !_forgot)
                TextButton(onPressed:account.isBusy?null:()=>setState(()=>_forgot=true),
                  child:const Text('Forgot password?',style:TextStyle(color:JarvisColors.cyan))),
              TextButton(onPressed:account.isBusy?null:()=>setState((){
                if(_forgot){_forgot=false;_questionLoaded=false;_answer.clear();_newPassword.clear();}
                else {_signup=!_signup;_answer.clear();}
              }),child:Text(_forgot?'Back to log in':(_signup?'Already have an account? Log in':'New to JARVIS? Create an account'),
                style:const TextStyle(color:JarvisColors.cyan))),
              const SizedBox(height:10),
              const Text('Your chats and memories sync securely to your account and follow you across devices.',
                textAlign:TextAlign.center,style:TextStyle(color:JarvisColors.textDim,fontSize:11,height:1.5)),
            ]),
          ),
        ),
      )),
    );
  }

  Future<void> _submit(AccountService account) async {
    FocusScope.of(context).unfocus();
    final username=_username.text.trim();
    if (_forgot) {
      if (!_questionLoaded) {
        final q=await account.fetchRecoveryQuestion(username);
        if (q!=null && mounted) setState(()=>_questionLoaded=true);
      } else {
        final ok=await account.resetPassword(username,_answer.text,_newPassword.text);
        if(ok && mounted) setState((){
          _forgot=false;_questionLoaded=false;_answer.clear();_newPassword.clear();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Password reset. Log in with your new password.')));
        });
      }
      return;
    }
    final ok=_signup
      ? await account.signUp(username,_password.text,_question,_answer.text)
      : await account.login(username,_password.text);
    if (ok && mounted) {
      await context.read<JarvisService>().setAccountToken(account.token!);
      await context.read<MemoryService>().setAccountToken(account.token!);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Welcome, ${account.username}.')));
    }
  }
}


class RecoverySetupScreen extends StatefulWidget {
  const RecoverySetupScreen({super.key});
  @override State<RecoverySetupScreen> createState() => _RecoverySetupScreenState();
}
class _RecoverySetupScreenState extends State<RecoverySetupScreen> {
  final _answer = TextEditingController();
  String _question = 'first_school';
  static const _questions = <String,String>{
    'first_school':'What was the name of your first school?',
    'childhood_friend':'What was the first name of your childhood best friend?',
    'first_pet':'What was the name of your first pet?',
    'birth_city':'In which city were you born?',
    'favourite_teacher':'What was the surname of a favourite teacher?',
  };
  @override void dispose() { _answer.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final account=context.watch<AccountService>();
    return Scaffold(backgroundColor:JarvisColors.background,
      body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),
        child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),
          child:Container(padding:const EdgeInsets.all(28),
            decoration:BoxDecoration(color:JarvisColors.surface,borderRadius:BorderRadius.circular(22),
              border:Border.all(color:JarvisColors.cyan.withOpacity(.3))),
            child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              const Icon(Icons.security_rounded,color:JarvisColors.cyan,size:46),
              const SizedBox(height:16),
              const Text('Secure your JARVIS account',textAlign:TextAlign.center,
                style:TextStyle(color:JarvisColors.textPrimary,fontSize:20,fontWeight:FontWeight.bold)),
              const SizedBox(height:10),
              const Text('Before continuing, set a recovery question. You will need it to reset your password if you forget it.',
                textAlign:TextAlign.center,style:TextStyle(color:JarvisColors.textDim,fontSize:12,height:1.5)),
              const SizedBox(height:22),
              DropdownButtonFormField<String>(value:_question,isExpanded:true,dropdownColor:JarvisColors.surface,
                style:const TextStyle(color:JarvisColors.textPrimary),decoration:const InputDecoration(labelText:'Recovery question'),
                items:_questions.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value,overflow:TextOverflow.ellipsis))).toList(),
                onChanged:(v){if(v!=null)setState(()=>_question=v);}),
              const SizedBox(height:14),
              TextField(controller:_answer,autocorrect:false,enableSuggestions:false,
                style:const TextStyle(color:JarvisColors.textPrimary),
                decoration:const InputDecoration(labelText:'Your recovery answer',prefixIcon:Icon(Icons.lock_outline))),
              if(account.error!=null)...[
                const SizedBox(height:12),
                Text(account.error!,style:const TextStyle(color:JarvisColors.red,fontSize:12)),
              ],
              const SizedBox(height:20),
              SizedBox(height:50,child:ElevatedButton(onPressed:account.isBusy?null:()async{
                final ok=await account.setRecoveryQuestion(_question,_answer.text);
                if(ok && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Recovery question saved. Your account is secured.')));
              },style:ElevatedButton.styleFrom(backgroundColor:JarvisColors.cyan,foregroundColor:JarvisColors.background),
                child:account.isBusy?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):
                  const Text('SAVE AND CONTINUE',style:TextStyle(fontWeight:FontWeight.bold,letterSpacing:1.5)))),
            ]),
          ),
        ),
      )),
    );
  }
}
