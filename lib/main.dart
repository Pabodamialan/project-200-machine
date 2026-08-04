import 'dart:async';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyC6E9L9PeC6_iKwYdZQK7QhlsUln1XG7ng",
        authDomain: "project200machine-5559d.firebaseapp.com",
        projectId: "project200machine-5559d",
        storageBucket: "project200machine-5559d.firebasestorage.app",
        messagingSenderId: "450612378006",
        appId: "1:450612378006:web:76ba286c338e94da8f45b7",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Project 200 Machine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: AuthGate(key: UniqueKey()),
    );
  }
}
// ---------------- AUTH GATE (auto-login check) ----------------
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _cachedUid;
  Future<DocumentSnapshot>? _userFuture;
  late final Stream<User?> _authStream = FirebaseAuth.instance.authStateChanges();

  Future<DocumentSnapshot> _getUserDoc(String uid) {
    if (_cachedUid != uid || _userFuture == null) {
      _cachedUid = uid;
      _userFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 15));
    }
    return _userFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
          );
        }

        final user = authSnapshot.data;

        if (user == null) {
          _cachedUid = null;
          _userFuture = null;
          return const LoginScreen();
        }

        return FutureBuilder<DocumentSnapshot>(
          future: _getUserDoc(user.uid),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                body: Container(
                  decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
                  child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              );
            }

            if (userSnapshot.hasError) {
              return Scaffold(
                body: Container(
                  decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Error: ${userSnapshot.error}',
                            style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          child: const Text('Back to Login'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              FirebaseAuth.instance.signOut();
              return const LoginScreen();
            }

            final data = userSnapshot.data!.data() as Map<String, dynamic>;
            final role = data['role'] ?? '';
            final name = data['name'] ?? '';

            switch (role) {
              case 'admin':
                return AdminDashboard(name: name);
              case 'owner':
                return OwnerDashboard(name: name);
              case 'supervisor':
                return SupervisorScreen(name: name);
              case 'driver':
                return DriverTypeScreen(name: name);
              case 'field_worker':
                final canDrive = data['canDriveTruck'] == true;
                final canOperate = data['canOperateMachine'] == true;
                if (canDrive && canOperate) {
                  return DriverTypeScreen(name: name);
                } else if (canDrive) {
                  return TruckTypeScreen(name: name);
                } else if (canOperate) {
                  return DriverMachineTypeScreen(name: name);
                } else {
                  FirebaseAuth.instance.signOut();
                  return const LoginScreen();
                }
              default:
                FirebaseAuth.instance.signOut();
                return const LoginScreen();
            }
          },
        );
      },
    );
  }
}
// ---------------- LOGIN SCREEN ----------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  bool _obscurePassword = true;

  VideoPlayerController? _videoController;
  bool _videoInitialized = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Uri.parse on a bare relative path has no scheme/host, which the
      // video_player web backend can't turn into a network request at all —
      // resolving against the page's own URL is what actually gives it
      // something fetchable.
      final videoUri = Uri.base.resolve('assets/videos/login_bg.mp4');
      final controller = VideoPlayerController.networkUrl(videoUri);
      _videoController = controller;
      controller.initialize().then((_) {
        if (!mounted) return;
        controller.setLooping(true);
        controller.setVolume(0.0);
        controller.play();
        setState(() => _videoInitialized = true);
      }).catchError((Object e, StackTrace st) {
        debugPrint('Login background video failed to initialize: $e');
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Step 1: Sign in with Firebase Auth
      final userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      ).timeout(const Duration(seconds: 20));

      final uid = userCredential.user!.uid;

      // Step 2: Fetch role from Firestore "users" collection
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userDoc.exists) {
        setState(() {
          _errorMessage = 'User profile not found in database.';
          _isLoading = false;
        });
        return;
      }

      final role = userDoc.data()?['role'] ?? '';
      final name = userDoc.data()?['name'] ?? '';

      if (!mounted) return;

      if (role != 'admin' &&
          role != 'owner' &&
          role != 'supervisor' &&
          role != 'driver' &&
          role != 'field_worker') {
        setState(() {
          _errorMessage = 'Unknown role. Contact Admin.';
        });
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (role == 'field_worker' &&
          userDoc.data()?['canDriveTruck'] != true &&
          userDoc.data()?['canOperateMachine'] != true) {
        setState(() {
          _errorMessage = 'Account not configured. Contact Admin.';
        });
        await FirebaseAuth.instance.signOut();
        return;
      }

      // Force navigation directly instead of relying solely on AuthGate's stream rebuild
      Widget target;
      switch (role) {
        case 'admin':
          target = AdminDashboard(name: name);
          break;
        case 'owner':
          target = OwnerDashboard(name: name);
          break;
        case 'supervisor':
          target = SupervisorScreen(name: name);
          break;
        case 'driver':
          target = DriverTypeScreen(name: name);
          break;
        case 'field_worker':
          final canDrive = userDoc.data()?['canDriveTruck'] == true;
          final canOperate = userDoc.data()?['canOperateMachine'] == true;
          if (canDrive && canOperate) {
            target = DriverTypeScreen(name: name);
          } else if (canDrive) {
            target = TruckTypeScreen(name: name);
          } else {
            target = DriverMachineTypeScreen(name: name);
          }
          break;
        default:
          target = const LoginScreen();
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => target),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Login failed. Please try again.';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Something went wrong. Try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 700;

    final loginContent = SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 440 : double.infinity,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(scale: value, child: child);
                    },
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accent.withOpacity(0.4),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(
                          'assets/images/logo_final_gradient.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'NODA Civimech Engineering',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Login to continue',
                    style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 36),
                  LoginFormCard(
                    child: Column(
                      children: [
                        TextField(
                          controller: _emailController,
                          style: const TextStyle(color: Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Email',
                            labelStyle: TextStyle(color: Colors.grey[700]),
                            prefixIcon: Icon(Icons.email, color: Colors.grey[700]),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[400]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.primaryMid, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: TextStyle(color: Colors.grey[700]),
                            prefixIcon: Icon(Icons.lock, color: Colors.grey[700]),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                color: Colors.grey[700],
                              ),
                              onPressed: () {
                                setState(() => _obscurePassword = !_obscurePassword);
                              },
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[400]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.primaryMid, width: 2),
                            ),
                          ),
                        ),
                        if (_errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 24),
                        _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : GradientButton(
                                label: 'LOGIN',
                                icon: Icons.login,
                                onTap: _login,
                              ),
                      ],
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
        );

    return Scaffold(
      body: kIsWeb
          ? Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/login_background_web.png',
                    fit: BoxFit.cover,
                  ),
                ),
                if (_videoInitialized && _videoController != null)
                  Positioned.fill(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _videoController!.value.size.width,
                        height: _videoController!.value.size.height,
                        child: VideoPlayer(_videoController!),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.primaryDark.withOpacity(0.45),
                          AppTheme.primaryMid.withOpacity(0.45),
                        ],
                      ),
                    ),
                  ),
                ),
                loginContent,
              ],
            )
          : Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/login_background.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: loginContent,
            ),
    );
  }
}

// ---------------- ADMIN DASHBOARD ----------------
class AdminDashboard extends StatelessWidget {
  final String name;
  const AdminDashboard({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    Future<void> logout() async {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }

    final bodyContent = SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome, $name (Admin)',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _WebStaggeredFadeIn(
            index: 0,
            child: _buildMenuCard(
              context,
              icon: Icons.person_add,
              title: 'Add Supervisor / Owner',
              subtitle: 'Create new user accounts',
              color: Colors.blue,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddUserScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _WebStaggeredFadeIn(
            index: 1,
            child: _buildMenuCard(
              context,
              icon: Icons.list_alt,
              title: 'Manage Users',
              subtitle: 'View, edit or remove users',
              color: Colors.indigo,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageUsersScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _WebStaggeredFadeIn(
            index: 2,
            child: _buildMenuCard(
              context,
              icon: Icons.precision_manufacturing,
              title: 'Manage Machines',
              subtitle: 'Add or view construction machines',
              color: Colors.orange,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MachineManagementScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _WebStaggeredFadeIn(
            index: 3,
            child: _buildMenuCard(
              context,
              icon: Icons.location_on,
              title: 'Manage Sites',
              subtitle: 'Add or view construction sites',
              color: Colors.teal,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SiteManagementScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _WebStaggeredFadeIn(
            index: 4,
            child: _buildMenuCard(
              context,
              icon: Icons.history,
              title: 'Site History',
              subtitle: 'View work history by site',
              color: Colors.deepPurple,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminSiteListScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _WebStaggeredFadeIn(
            index: 5,
            child: _buildMenuCard(
              context,
              icon: Icons.local_shipping,
              title: 'Manage Trucks',
              subtitle: 'Add or view trucks',
              color: Colors.deepOrange,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TruckManagementScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.blue[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: logout,
          ),
        ],
      ),
      body: WebAppShell(
        appName: 'NODA Admin',
        onLogout: logout,
        menuItems: [
          WebSidebarItem(icon: Icons.dashboard, label: 'Dashboard', onTap: () {}),
          WebSidebarItem(
            icon: Icons.list_alt,
            label: 'Users',
            onTap: () => Navigator.push(
              context,
              FadeSlideRoute(page: const ManageUsersScreen()),
            ),
          ),
          WebSidebarItem(
            icon: Icons.precision_manufacturing,
            label: 'Machines',
            onTap: () => Navigator.push(
              context,
              FadeSlideRoute(page: const MachineManagementScreen()),
            ),
          ),
          WebSidebarItem(
            icon: Icons.location_on,
            label: 'Sites',
            onTap: () => Navigator.push(
              context,
              FadeSlideRoute(page: const SiteManagementScreen()),
            ),
          ),
          WebSidebarItem(
            icon: Icons.local_shipping,
            label: 'Trucks',
            onTap: () => Navigator.push(
              context,
              FadeSlideRoute(page: const TruckManagementScreen()),
            ),
          ),
          WebSidebarItem(
            icon: Icons.bar_chart,
            label: 'Reports',
            onTap: () => Navigator.push(
              context,
              FadeSlideRoute(page: const AdminSiteListScreen()),
            ),
          ),
        ],
        child: bodyContent,
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ---------------- ADD USER SCREEN (Admin creates Supervisor/Owner) ----------------
class AddUserScreen extends StatefulWidget {
  const AddUserScreen({super.key});

  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = 'supervisor';
  bool _canDriveTruck = false;
  bool _canOperateMachine = false;
  bool _isLoading = false;
  String _message = '';
  bool _isError = false;
  String? _photoBase64;

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 60,
      );
      if (pickedFile == null) return;

      final bytes = await pickedFile.readAsBytes();
      final base64String = base64Encode(bytes);

      // Firestore document limit is 1MB; keep a safety margin
      if (base64String.length > 700000) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image too large. Please choose a smaller photo.')),
          );
        }
        return;
      }

      setState(() => _photoBase64 = base64String);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_photoBase64 != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Photo'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _photoBase64 = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createUser() async {
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().length < 6) {
      setState(() {
        _isError = true;
        _message = 'Please fill all fields. Password must be 6+ characters.';
      });
      return;
    }

    if (_selectedRole == 'field_worker' && !_canDriveTruck && !_canOperateMachine) {
      setState(() {
        _isError = true;
        _message = 'Please select at least one: Driver or Operator.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = '';
    });

    try {
      // Use a SECONDARY Firebase app so the Admin doesn't get logged out
      FirebaseApp tempApp = await Firebase.initializeApp(
        name: 'tempApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      FirebaseAuth tempAuth = FirebaseAuth.instanceFor(app: tempApp);

      UserCredential newUser = await tempAuth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Save role info in Firestore "users" collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(newUser.user!.uid)
          .set({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': _selectedRole,
        'canDriveTruck': _selectedRole == 'field_worker' ? _canDriveTruck : false,
        'canOperateMachine': _selectedRole == 'field_worker' ? _canOperateMachine : false,
        'photoBase64': _photoBase64,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Sign out and delete the temporary app instance
      await tempAuth.signOut();
      await tempApp.delete();

      setState(() {
        _isError = false;
        _message = 'Account created successfully!';
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _photoBase64 = null;
        _canDriveTruck = false;
        _canOperateMachine = false;
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isError = true;
        _message = e.message ?? 'Failed to create user.';
      });
    } catch (e) {
      setState(() {
        _isError = true;
        _message = 'Something went wrong: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Supervisor / Owner'),
        backgroundColor: Colors.blue[800],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: GestureDetector(
                onTap: _showPhotoSourceSheet,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.blue[100],
                      backgroundImage: _photoBase64 != null
                          ? MemoryImage(base64Decode(_photoBase64!))
                          : null,
                      child: _photoBase64 == null
                          ? Icon(Icons.person, size: 50, color: Colors.blue[800])
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue[800],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Tap to add photo (optional)',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Select Role', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Column(
              children: [
                RadioListTile<String>(
                  title: const Text('Supervisor'),
                  value: 'supervisor',
                  groupValue: _selectedRole,
                  onChanged: (val) => setState(() => _selectedRole = val!),
                ),
                RadioListTile<String>(
                  title: const Text('Owner'),
                  value: 'owner',
                  groupValue: _selectedRole,
                  onChanged: (val) => setState(() => _selectedRole = val!),
                ),
                RadioListTile<String>(
                  title: const Text('Field Worker (Driver / Operator)'),
                  value: 'field_worker',
                  groupValue: _selectedRole,
                  onChanged: (val) => setState(() => _selectedRole = val!),
                ),
                if (_selectedRole == 'field_worker')
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('What can they operate?',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          CheckboxListTile(
                            title: const Text('Driver (can operate trucks)'),
                            value: _canDriveTruck,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (val) => setState(() => _canDriveTruck = val ?? false),
                          ),
                          CheckboxListTile(
                            title: const Text('Operator (can operate machines)'),
                            value: _canOperateMachine,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (val) => setState(() => _canOperateMachine = val ?? false),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Full Name',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password (min 6 characters)',
                prefixIcon: const Icon(Icons.lock),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _message,
                  style: TextStyle(color: _isError ? Colors.red : Colors.green, fontSize: 13),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createUser,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[800],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('CREATE ACCOUNT', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- MANAGE USERS SCREEN ----------------
class ManageUsersScreen extends StatelessWidget {
  const ManageUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        backgroundColor: Colors.blue[800],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No users found.'));
          }

          final users = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final data = users[index].data() as Map<String, dynamic>;
              final role = data['role'] ?? '';
              Color roleColor = role == 'admin'
                  ? Colors.blue
                  : role == 'owner'
                      ? Colors.green
                      : Colors.orange;

              final userId = users[index].id;
              final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
              final isSelf = userId == currentUserUid;
              final photoBase64 = data['photoBase64'] as String?;

              return _WebStaggeredFadeIn(
                index: index,
                child: _WebHoverCard(
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: roleColor.withOpacity(0.15),
                        backgroundImage:
                            photoBase64 != null ? MemoryImage(base64Decode(photoBase64)) : null,
                        child: photoBase64 == null ? Icon(Icons.person, color: roleColor) : null,
                      ),
                      title: Text(data['name'] ?? 'No name'),
                      subtitle: Text('${data['email'] ?? ''}\nRole: $role'),
                      isThreeLine: true,
                      onTap: () {
                        pushWebAware(
                          context,
                          UserProfileScreen(
                            userId: userId,
                            userName: data['name'] ?? '',
                            userEmail: data['email'] ?? '',
                            userRole: role,
                            photoBase64: photoBase64,
                          ),
                        );
                      },
                      trailing: isSelf
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Delete User'),
                                    content: Text(
                                        'Remove access for ${data['name'] ?? 'this user'}? They will no longer be able to use the app.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () async {
                                          await FirebaseFirestore.instance
                                              .collection('users')
                                              .doc(userId)
                                              .delete();
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('User access removed.')),
                                            );
                                          }
                                        },
                                        style:
                                            ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
                                        child: const Text('DELETE',
                                            style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}// ---------------- MACHINE MANAGEMENT SCREEN ----------------
class MachineManagementScreen extends StatefulWidget {
  const MachineManagementScreen({super.key});

  @override
  State<MachineManagementScreen> createState() => _MachineManagementScreenState();
}

class _MachineManagementScreenState extends State<MachineManagementScreen> {
  final _machineNameController = TextEditingController();
  final _machineNumberController = TextEditingController();
  String _selectedType = '200 Machine';

  final List<String> _machineTypes = [
    '200 Machine',
    '70 Machine',
    'Loader',
  ];

  Future<void> _addMachine() async {
    if (_machineNameController.text.trim().isEmpty ||
        _machineNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields.')),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('machines').add({
      'name': _machineNameController.text.trim(),
      'number': _machineNumberController.text.trim(),
      'type': _selectedType,
      'status': 'idle',
      'createdAt': FieldValue.serverTimestamp(),
    });

    _machineNameController.clear();
    _machineNumberController.clear();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Machine added successfully!')),
      );
    }
  }

  Future<void> _deleteMachine(String docId) async {
    await FirebaseFirestore.instance.collection('machines').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Machines'),
        backgroundColor: Colors.orange[800],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _machineNameController,
                  decoration: InputDecoration(
                    labelText: 'Machine Name (e.g. JCB 1)',
                    prefixIcon: const Icon(Icons.construction),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _machineNumberController,
                  decoration: InputDecoration(
                    labelText: 'Machine Number / Plate',
                    prefixIcon: const Icon(Icons.numbers),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedType,
                  decoration: InputDecoration(
                    labelText: 'Machine Type',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _machineTypes
                      .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                      .toList(),
                  onChanged: (val) => setState(() => _selectedType = val!),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _addMachine,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('ADD MACHINE', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('machines')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No machines added yet.'));
                }

                final machines = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: machines.length,
                  itemBuilder: (context, index) {
                    final data = machines[index].data() as Map<String, dynamic>;
                    final docId = machines[index].id;

                    return _WebStaggeredFadeIn(
                      index: index,
                      child: _WebHoverCard(
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.withOpacity(0.15),
                              child: const Icon(Icons.precision_manufacturing,
                                  color: Colors.orange),
                            ),
                            title: Text(data['name'] ?? ''),
                            subtitle: Text('${data['type'] ?? ''} • ${data['number'] ?? ''}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteMachine(docId),
                            ),
                            onTap: () {
                              pushWebAware(
                                context,
                                MachineProfileScreen(
                                  machineId: docId,
                                  machineName: data['name'] ?? '',
                                  machineType: data['type'] ?? '',
                                  machineNumber: data['number'] ?? '',
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- SITE MANAGEMENT SCREEN ----------------
class SiteManagementScreen extends StatefulWidget {
  const SiteManagementScreen({super.key});

  @override
  State<SiteManagementScreen> createState() => _SiteManagementScreenState();
}

class _SiteManagementScreenState extends State<SiteManagementScreen> {
  final _siteNameController = TextEditingController();
  final _siteLocationController = TextEditingController();
  bool _isPlantSite = false;
  bool _canBeLoadingSite = true;
  bool _canBeUnloadingSite = true;

  Future<void> _addSite() async {
    final enteredName = _siteNameController.text.trim();
    if (enteredName.isEmpty || _siteLocationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields.')),
      );
      return;
    }

    final existingSites = await FirebaseFirestore.instance.collection('sites').get();
    final normalizedEntry = enteredName.toUpperCase();
    final isDuplicate = existingSites.docs.any((doc) {
      final data = doc.data();
      final existingName = (data['name'] as String?)?.trim().toUpperCase() ?? '';
      return existingName == normalizedEntry;
    });

    if (isDuplicate) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This site is already registered.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await FirebaseFirestore.instance.collection('sites').add({
      'name': enteredName,
      'location': _siteLocationController.text.trim(),
      'isPlantSite': _isPlantSite,
      'canBeLoadingSite': _canBeLoadingSite,
      'canBeUnloadingSite': _canBeUnloadingSite,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _siteNameController.clear();
    _siteLocationController.clear();
    setState(() {
      _isPlantSite = false;
      _canBeLoadingSite = true;
      _canBeUnloadingSite = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Site added successfully!')),
      );
    }
  }

  Future<void> _deleteSite(String docId) async {
    await FirebaseFirestore.instance.collection('sites').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Sites'),
        backgroundColor: Colors.teal[800],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _siteNameController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Site Name',
                    prefixIcon: const Icon(Icons.location_city),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('sites').snapshots(),
                  builder: (context, snapshot) {
                    final query = _siteNameController.text.trim().toLowerCase();
                    if (query.isEmpty || !snapshot.hasData) return const SizedBox.shrink();
                    final matches = snapshot.data!.docs
                        .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String?)
                        .whereType<String>()
                        .where((name) => name.toLowerCase().contains(query))
                        .take(5)
                        .toList();
                    if (matches.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Similar sites already registered:',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: matches
                                .map((name) => Chip(
                                      label: Text(name, style: const TextStyle(fontSize: 12)),
                                      backgroundColor: Colors.orange[50],
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _siteLocationController,
                  decoration: InputDecoration(
                    labelText: 'Location / Address',
                    prefixIcon: const Icon(Icons.map),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Is this a Plant Site?'),
                  value: _isPlantSite,
                  onChanged: (val) => setState(() => _isPlantSite = val ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Can be selected as a Working Site?'),
                  value: _canBeLoadingSite,
                  onChanged: (val) => setState(() => _canBeLoadingSite = val ?? true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Can be selected as an Unloading Site?'),
                  value: _canBeUnloadingSite,
                  onChanged: (val) => setState(() => _canBeUnloadingSite = val ?? true),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _addSite,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('ADD SITE', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('sites')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No sites added yet.'));
                }

                final sites = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: sites.length,
                  itemBuilder: (context, index) {
                    final data = sites[index].data() as Map<String, dynamic>;
                    final docId = sites[index].id;

                    return _WebStaggeredFadeIn(
                      index: index,
                      child: _WebHoverCard(
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.teal.withOpacity(0.15),
                              child: const Icon(Icons.location_on, color: Colors.teal),
                            ),
                            title: Text(data['name'] ?? ''),
                            subtitle: Text([
                              data['location'] ?? '',
                              if (data['isPlantSite'] == true) '🏭 Plant Site',
                              if (data['canBeLoadingSite'] == false) '🚫 Not a Working Site',
                            ].where((s) => s.isNotEmpty).join('  •  ')),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteSite(docId),
                            ),
                            onTap: () => pushWebAware(
                              context,
                              SiteHistoryScreen(siteId: docId, siteName: data['name'] ?? ''),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
// ---------------- OWNER DASHBOARD ----------------
class OwnerDashboard extends StatelessWidget {
  final String name;
  const OwnerDashboard({super.key, required this.name});

  String _todayString() {
    final today = DateTime.now();
    return "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final todayDate = _todayString();

    Future<void> logout() async {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }

    final bodyContent = RefreshIndicator(
        onRefresh: () async {},
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome, $name',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Live overview — ${DateTime.now().toString().substring(0, 10)}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),

              // ---- Summary Cards ----
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('daily_sessions')
                    .where('date', isEqualTo: todayDate)
                    .snapshots(),
                builder: (context, snapshot) {
                  final sessions = snapshot.data?.docs ?? [];
                  final activeSessions =
                      sessions.where((d) => (d.data() as Map)['status'] == 'active').length;

                  return Row(
                    children: [
                      Expanded(
                        child: _WebStaggeredFadeIn(
                          index: 0,
                          child: _summaryCard(
                            'Active Machines',
                            activeSessions,
                            Icons.precision_manufacturing,
                            Colors.green,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _WebStaggeredFadeIn(
                          index: 1,
                          child: _summaryCard(
                            'Total Sessions Today',
                            sessions.length,
                            Icons.today,
                            Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              const Text('Today — Work Category Breakdown',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('daily_sessions')
                    .where('date', isEqualTo: todayDate)
                    .snapshots(),
                builder: (context, sessionSnap) {
                  if (!sessionSnap.hasData || sessionSnap.data!.docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No data yet for today.'),
                    );
                  }

                  return FutureBuilder<Map<String, int>>(
                    future: _calculateCategoryLoadCounts(sessionSnap.data!.docs),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final totals = snapshot.data!;
                      if (totals.isEmpty || totals.values.every((v) => v == 0)) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text('No loads completed yet today.'),
                        );
                      }

                      final colors = [
                        Colors.orange,
                        Colors.blue,
                        Colors.green,
                        Colors.purple,
                        Colors.red,
                        Colors.teal,
                        Colors.brown,
                        Colors.indigo,
                      ];

                      final entries = totals.entries.toList();

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 180,
                                child: PieChart(
                                  PieChartData(
                                    sectionsSpace: 2,
                                    centerSpaceRadius: 40,
                                    sections: List.generate(entries.length, (i) {
                                      final count = entries[i].value;
                                      return PieChartSectionData(
                                        value: count.toDouble(),
                                        title: '$count',
                                        color: colors[i % colors.length],
                                        radius: 55,
                                        titleStyle: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white),
                                      );
                                    }),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: List.generate(entries.length, (i) {
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: colors[i % colors.length],
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(entries[i].key, style: const TextStyle(fontSize: 12)),
                                    ],
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 24),

              _WebStaggeredFadeIn(
                index: 2,
                child: DashboardMenuCard(
                  icon: Icons.location_on,
                  title: 'Sites',
                  subtitle: 'View all sites and their history',
                  color: Colors.teal,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminSiteListScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _WebStaggeredFadeIn(
                index: 3,
                child: DashboardMenuCard(
                  icon: Icons.groups,
                  title: 'Team',
                  subtitle: 'View supervisors and drivers',
                  color: Colors.deepPurple,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TeamCategoryScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              const Text('Live Machine Status',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('daily_sessions')
                    .where('date', isEqualTo: todayDate)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No machines working today.'),
                    );
                  }

                  // Sort client-side by createdAt (avoids needing a
                  // composite Firestore index for date + createdAt).
                  final sessions = snapshot.data!.docs.toList()
                    ..sort((a, b) {
                      final aTs = (a.data() as Map)['createdAt'] as Timestamp?;
                      final bTs = (b.data() as Map)['createdAt'] as Timestamp?;
                      if (aTs == null || bTs == null) return 0;
                      return bTs.compareTo(aTs);
                    });

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final sData = session.data() as Map<String, dynamic>;
                      final isActive = sData['status'] == 'active';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      sData['machineName'] ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isActive ? Colors.green : Colors.grey,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      isActive ? 'ACTIVE' : 'COMPLETED',
                                      style: const TextStyle(color: Colors.white, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Site: ${sData['siteName']} • Supervisor: ${sData['supervisorName']}',
                                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
                              const Divider(height: 16),

                              // Current work record (running one)
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('daily_sessions')
                                    .doc(session.id)
                                    .collection('work_records')
                                    .where('status', isEqualTo: 'running')
                                    .limit(1)
                                    .snapshots(),
                                builder: (context, workSnap) {
                                  if (!workSnap.hasData || workSnap.data!.docs.isEmpty) {
                                    return const Text('No active work right now',
                                        style: TextStyle(fontSize: 13, color: Colors.grey));
                                  }
                                  final workData =
                                      workSnap.data!.docs.first.data() as Map<String, dynamic>;
                                  return Row(
                                    children: [
                                      const Icon(Icons.play_circle_fill, color: Colors.green, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Working: ${workData['category']}',
                                        style: const TextStyle(
                                            fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Dashboard'),
        backgroundColor: Colors.green[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: logout,
          ),
        ],
      ),
      body: WebAppShell(
        appName: 'NODA Owner',
        onLogout: logout,
        menuItems: [
          WebSidebarItem(icon: Icons.dashboard, label: 'Dashboard', onTap: () {}),
          WebSidebarItem(
            icon: Icons.location_on,
            label: 'Sites',
            onTap: () => Navigator.push(
              context,
              FadeSlideRoute(page: const AdminSiteListScreen()),
            ),
          ),
          WebSidebarItem(
            icon: Icons.groups,
            label: 'Team',
            onTap: () => Navigator.push(
              context,
              FadeSlideRoute(page: const TeamCategoryScreen()),
            ),
          ),
        ],
        child: bodyContent,
      ),
    );
  }
Future<Map<String, int>> _calculateCategoryLoadCounts(List<QueryDocumentSnapshot> sessions) async {
    final Map<String, int> loadCountsByCategory = {};

    for (final session in sessions) {
      final recordsSnap = await FirebaseFirestore.instance
          .collection('daily_sessions')
          .doc(session.id)
          .collection('work_records')
          .get();

      for (final rec in recordsSnap.docs) {
        final data = rec.data();
        if (data['isCompleted'] != true) continue;

        final category = data['category'] ?? 'Unknown';
        loadCountsByCategory[category] = (loadCountsByCategory[category] ?? 0) + 1;
      }
    }

    return loadCountsByCategory;
  }
  Widget _summaryCard(String label, int value, IconData icon, Color color) {
    const valueStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            kIsWeb
                ? TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: value),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    builder: (context, animatedValue, _) =>
                        Text('$animatedValue', style: valueStyle),
                  )
                : Text('$value', style: valueStyle),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ---------------- SUPERVISOR SCREEN ----------------
class SupervisorScreen extends StatefulWidget {
  final String name;
  const SupervisorScreen({super.key, required this.name});

  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _SupervisorScreenState extends State<SupervisorScreen> {
  String? _selectedMachineId;
  String? _selectedMachineName;
  String? _selectedSiteId;
  String? _selectedSiteName;
  final _startMeterController = TextEditingController();
  bool _isLoading = false;
  bool _checkingActiveSession = true;

  @override
  void initState() {
    super.initState();
    _checkForActiveSession();
  }

  Future<void> _checkForActiveSession() async {
    try {
      final today = DateTime.now();
      final dateString =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      final existing = await FirebaseFirestore.instance
          .collection('daily_sessions')
          .where('supervisorUid', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .where('date', isEqualTo: dateString)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty && mounted) {
        final data = existing.docs.first.data();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WorkSessionScreen(
              sessionId: existing.docs.first.id,
              machineName: data['machineName'] ?? '',
              siteName: data['siteName'] ?? '',
              siteId: data['siteId'] ?? '',
              supervisorName: widget.name,
              verificationCode: data['verificationCode'],
            ),
          ),
        );
        return;
      }
    } catch (e) {
      // If offline or error, just fall through to the normal selection screen
    }
    if (mounted) setState(() => _checkingActiveSession = false);
  }

  Future<void> _startDay() async {
    if (_selectedMachineId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a machine.')),
      );
      return;
    }
    if (_selectedSiteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a site.')),
      );
      return;
    }
    if (_startMeterController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter start meter reading.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final today = DateTime.now();
      final dateString =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      // Check if there's already an active session today for this machine
      final existing = await FirebaseFirestore.instance
          .collection('daily_sessions')
          .where('machineId', isEqualTo: _selectedMachineId)
          .where('date', isEqualTo: dateString)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      String sessionId;

      if (existing.docs.isNotEmpty) {
        // Resume existing session for today
        sessionId = existing.docs.first.id;
      } else {
        // Check if this SITE already has a verification code generated today
        // (any supervisor at this site should share the same code)
        final siteToday = await FirebaseFirestore.instance
            .collection('daily_sessions')
            .where('siteId', isEqualTo: _selectedSiteId)
            .where('date', isEqualTo: dateString)
            .limit(1)
            .get();

        String verificationCode;
        if (siteToday.docs.isNotEmpty &&
            siteToday.docs.first.data()['verificationCode'] != null) {
          // Reuse the existing code for this site today
          verificationCode = siteToday.docs.first.data()['verificationCode'];
        } else {
          // First session at this site today - generate a new code
          verificationCode = (1000 + Random().nextInt(9000)).toString();
        }

        // Create new daily session
        final docRef = await FirebaseFirestore.instance.collection('daily_sessions').add({
          'supervisorUid': FirebaseAuth.instance.currentUser!.uid,
          'supervisorName': widget.name,
          'machineId': _selectedMachineId,
          'machineName': _selectedMachineName,
          'siteId': _selectedSiteId,
          'siteName': _selectedSiteName,
          'startMeter': double.tryParse(_startMeterController.text.trim()) ?? 0,
          'endMeter': null,
          'date': dateString,
          'status': 'active',
          'verificationCode': verificationCode,
          'createdAt': FieldValue.serverTimestamp(),
        });
        sessionId = docRef.id;
      }

      if (mounted) {
        final sessionDoc = await FirebaseFirestore.instance
            .collection('daily_sessions')
            .doc(sessionId)
            .get();
        final code = sessionDoc.data()?['verificationCode'] as String?;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WorkSessionScreen(
              sessionId: sessionId,
              machineName: _selectedMachineName ?? '',
              siteName: _selectedSiteName ?? '',
              siteId: _selectedSiteId ?? '',
              supervisorName: widget.name,
              verificationCode: code,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Searchable site picker — only lets the supervisor pick an existing
  // registered site (unlike the Unloading Site Autocomplete elsewhere,
  // which allows free text). Sites missing the canBeLoadingSite field
  // entirely are treated as eligible, so pre-existing sites registered
  // before this field existed don't silently disappear from the list.
  Future<void> _showSiteSearchPicker() async {
    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        String searchText = '';
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.75,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search site name',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (val) => setSheetState(() => searchText = val),
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('sites').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final filtered = snapshot.data!.docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            if (data['canBeLoadingSite'] == false) return false;
                            final name = (data['name'] ?? '').toString();
                            return name.toLowerCase().contains(searchText.toLowerCase());
                          }).toList();
                          if (filtered.isEmpty) {
                            return const Center(child: Text('No matching sites.'));
                          }
                          return ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final doc = filtered[index];
                              final data = doc.data() as Map<String, dynamic>;
                              return ListTile(
                                leading: const Icon(Icons.location_on, color: Colors.teal),
                                title: Text(data['name'] ?? ''),
                                subtitle: Text(data['location'] ?? ''),
                                onTap: () => Navigator.pop(sheetContext, {
                                  'id': doc.id,
                                  'name': (data['name'] ?? '').toString(),
                                }),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedSiteId = selected['id'];
        _selectedSiteName = selected['name'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingActiveSession) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
          child: const Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Welcome, ${widget.name}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: (kIsWeb && MediaQuery.of(context).size.width > 700)
                            ? 500
                            : double.infinity,
                      ),
                      child: GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _WebStaggeredFadeIn(
                              index: 0,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Select Machine',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(height: 8),
                                  StreamBuilder<QuerySnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection('machines')
                                        .snapshots(),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) {
                                        return const CircularProgressIndicator();
                                      }
                                      final machines = snapshot.data!.docs;
                                      return DropdownButtonFormField<String>(
                                        initialValue: _selectedMachineId,
                                        decoration: InputDecoration(
                                          hintText: 'Choose a machine',
                                          prefixIcon:
                                              const Icon(Icons.precision_manufacturing),
                                          border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12)),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        items: machines.map((doc) {
                                          final data = doc.data() as Map<String, dynamic>;
                                          return DropdownMenuItem<String>(
                                            value: doc.id,
                                            child: Text('${data['name']} (${data['type']})'),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          final selected =
                                              machines.firstWhere((d) => d.id == val);
                                          final data =
                                              selected.data() as Map<String, dynamic>;
                                          setState(() {
                                            _selectedMachineId = val;
                                            _selectedMachineName = data['name'];
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            _WebStaggeredFadeIn(
                              index: 1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Select Site',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(height: 8),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: _showSiteSearchPicker,
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        prefixIcon: const Icon(Icons.location_on),
                                        border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12)),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                      child: Text(
                                        _selectedSiteName ?? 'Choose a site',
                                        style: TextStyle(
                                          color: _selectedSiteName == null
                                              ? Colors.grey[600]
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            _WebStaggeredFadeIn(
                              index: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Start Meter Reading',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _startMeterController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      hintText: 'e.g. 1234.5',
                                      prefixIcon: const Icon(Icons.speed),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12)),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            _WebStaggeredFadeIn(
                              index: 3,
                              child: _isLoading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : GradientButton(
                                      label: 'START DAY / CONTINUE',
                                      icon: Icons.play_arrow,
                                      onTap: _startDay,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- WORK SESSION SCREEN ----------------
class WorkSessionScreen extends StatefulWidget {
  final String sessionId;
  final String machineName;
  final String siteName;
  final String siteId;
  final String supervisorName;
  final String? verificationCode;

  const WorkSessionScreen({
    super.key,
    required this.sessionId,
    required this.machineName,
    required this.siteName,
    required this.siteId,
    required this.supervisorName,
    this.verificationCode,
  });

  @override
  State<WorkSessionScreen> createState() => _WorkSessionScreenState();
}

class _WorkSessionScreenState extends State<WorkSessionScreen> {
  Timer? _tickTimer;

  final List<String> _loadingCategories = [
    'Sand Loading',
    'Soil Loading',
    'Rock Loading',
  ];

  final List<String> _otherCategories = [
    'Road Cleaning',
    'Travelling',
    'Idle',
    'Fuel Filling',
    'Maintenance',
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  CollectionReference get _recordsRef => FirebaseFirestore.instance
      .collection('daily_sessions')
      .doc(widget.sessionId)
      .collection('work_records');

  // Pause any currently running record in this session
  Future<void> _pauseRunningRecord() async {
    final runningSnap =
        await _recordsRef.where('status', isEqualTo: 'running').get();

    for (final doc in runningSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final lastResumedAt = (data['lastResumedAt'] as Timestamp?)?.toDate();
      final currentTotal = (data['totalDurationSeconds'] ?? 0) as int;

      int addedSeconds = 0;
      if (lastResumedAt != null) {
        addedSeconds = DateTime.now().difference(lastResumedAt).inSeconds;
      }

      await doc.reference.update({
        'status': 'paused',
        'totalDurationSeconds': currentTotal + addedSeconds,
        'lastResumedAt': null,
      });
    }
  }

  // Resume a specific paused record (pauses whatever else is running first)
  Future<void> _resumeRecord(String recordId) async {
    await _pauseRunningRecord();
    await _recordsRef.doc(recordId).update({
      'status': 'running',
      'lastResumedAt': FieldValue.serverTimestamp(),
    });
  }

  // Start a brand new work record
  Future<void> _startNewWork({
    required String category,
    required bool isLoadingCategory,
    String? truckNumber,
    String? billNumber,
    String? unloadingSiteName,
    double? distanceKm,
    String? truckDriverName,
    String? cubeCount,
    String? machineOperatorName,
  }) async {
    await _pauseRunningRecord();

    // Only the day's first Loading task inherits the day-level start meter;
    // meter tracking beyond that point happens at the day level (see
    // _showEndDayDialog), not per task.
    double? startMeter;
    if (isLoadingCategory) {
      final existingLoadingSnap =
          await _recordsRef.where('isLoadingCategory', isEqualTo: true).limit(1).get();
      if (existingLoadingSnap.docs.isEmpty) {
        final sessionDoc = await FirebaseFirestore.instance
            .collection('daily_sessions')
            .doc(widget.sessionId)
            .get();
        startMeter = (sessionDoc.data()?['startMeter'] as num?)?.toDouble();
      }
    }

    await _recordsRef.add({
      'category': category,
      'isLoadingCategory': isLoadingCategory,
      'status': 'running',
      'totalDurationSeconds': 0,
      'lastResumedAt': FieldValue.serverTimestamp(),
      'truckNumber': truckNumber,
      'billNumber': billNumber,
      'unloadingSiteName': unloadingSiteName,
      'distanceKm': distanceKm,
      'startMeter': startMeter,
      'endMeter': null,
      'truckDriverName': truckDriverName,
      'cubeCount': cubeCount,
      'machineOperatorName': machineOperatorName,
      'loadStartedAt': isLoadingCategory ? FieldValue.serverTimestamp() : null,
      'loadCompletedAt': null,
      'isCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Complete a loading record. Meter readings are no longer taken per task -
  // endMeter stays null here and only gets filled in for the day's last
  // Loading task when the supervisor ends the day (see _showEndDayDialog).
  Future<void> _completeLoadingRecord(String recordId) async {
    try {
      final doc = await _recordsRef.doc(recordId).get();
      final data = doc.data() as Map<String, dynamic>;
      final lastResumedAt = (data['lastResumedAt'] as Timestamp?)?.toDate();
      final currentTotal = (data['totalDurationSeconds'] ?? 0) as int;

      int addedSeconds = 0;
      if (lastResumedAt != null) {
        addedSeconds = DateTime.now().difference(lastResumedAt).inSeconds;
      }
      final newTotal = currentTotal + addedSeconds;

      await _recordsRef.doc(recordId).update({
        'status': 'paused',
        'totalDurationSeconds': newTotal,
        'lastResumedAt': null,
        'endMeter': null,
        'loadCompletedAt': FieldValue.serverTimestamp(),
        'isCompleted': true,
      });

      // Sync this completed load to Google Sheets
      final updatedDoc = await _recordsRef.doc(recordId).get();
      final updatedData = updatedDoc.data() as Map<String, dynamic>;

      final row = [
        GoogleSheetsService.formatDate(DateTime.now()),
        widget.machineName,
        widget.siteName,
        widget.supervisorName,
        updatedData['category'] ?? '',
        updatedData['truckNumber'] ?? '',
        updatedData['billNumber'] ?? '',
        updatedData['unloadingSiteName'] ?? '',
        updatedData['distanceKm']?.toString() ?? '',
        updatedData['startMeter']?.toString() ?? '',
        updatedData['endMeter']?.toString() ?? '',
        _formatDuration(newTotal),
        GoogleSheetsService.formatTime(updatedData['loadStartedAt']),
        GoogleSheetsService.formatTime(updatedData['loadCompletedAt']),
        updatedData['truckDriverName'] ?? '',
        updatedData['cubeCount'] ?? '',
        updatedData['machineOperatorName'] ?? '',
      ];

      GoogleSheetsService.sendRow(sheetName: 'Supervisor_Loads', row: row);

      // Plant sites also get a copy of every completed load in a dedicated
      // sheet, in addition to the regular Supervisor_Loads log.
      final siteDoc =
          await FirebaseFirestore.instance.collection('sites').doc(widget.siteId).get();
      if (siteDoc.data()?['isPlantSite'] == true) {
        GoogleSheetsService.sendRow(sheetName: 'Plant_Loads', row: row);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete load: $e')),
        );
      }
    }
  }

  int _liveElapsedSeconds(Map<String, dynamic> data) {
    final total = (data['totalDurationSeconds'] ?? 0) as int;
    if (data['status'] == 'running' && data['lastResumedAt'] != null) {
      final lastResumedAt = (data['lastResumedAt'] as Timestamp).toDate();
      final extra = DateTime.now().difference(lastResumedAt).inSeconds;
      return total + extra;
    }
    return total;
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showNewWorkDialog() {
    showDialog(
      context: context,
      builder: (_) => NewWorkDialog(
        loadingCategories: _loadingCategories,
        otherCategories: _otherCategories,
        currentSiteId: widget.siteId,
        onSubmit: (category, truckNumber, billNumber, unloadingSiteName, distanceKm, startMeter,
            truckDriverName, cubeCount, machineOperatorName) {
          Navigator.pop(context);
          _startNewWork(
            category: category,
            isLoadingCategory: _loadingCategories.contains(category),
            truckNumber: truckNumber,
            billNumber: billNumber,
            unloadingSiteName: unloadingSiteName,
            distanceKm: distanceKm,
            truckDriverName: truckDriverName,
            cubeCount: cubeCount,
            machineOperatorName: machineOperatorName,
          );
        },
      ),
    );
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '-';
    final dt = ts.toDate();
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
  void _showEndDayDialog() {
    final endMeterController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End Day'),
        content: TextField(
          controller: endMeterController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'End Meter Reading',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (endMeterController.text.trim().isEmpty) return;
              try {
                await _pauseRunningRecord();
                final endMeterValue = double.tryParse(endMeterController.text.trim()) ?? 0;

                await FirebaseFirestore.instance
                    .collection('daily_sessions')
                    .doc(widget.sessionId)
                    .update({
                  'endMeter': endMeterValue,
                  'status': 'completed',
                  'completedAt': FieldValue.serverTimestamp(),
                });

                // Stamp the day's last Loading task with the same end meter.
                // No orderBy here on purpose: pairing it with the equality
                // filter above would require a composite Firestore index
                // that isn't provisioned for this project, which made this
                // query throw FAILED_PRECONDITION and abort the handler
                // before the dialog could close.
                final loadingSnap =
                    await _recordsRef.where('isLoadingCategory', isEqualTo: true).get();
                if (loadingSnap.docs.isNotEmpty) {
                  QueryDocumentSnapshot? lastLoadingDoc;
                  Timestamp? lastLoadingTime;
                  for (final candidate in loadingSnap.docs) {
                    final candidateTime =
                        (candidate.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                    if (lastLoadingDoc == null) {
                      // First candidate always starts as the current pick.
                      lastLoadingDoc = candidate;
                      lastLoadingTime = candidateTime;
                    } else if (lastLoadingTime == null) {
                      // Current pick has no createdAt to compare against; any
                      // later candidate replaces it.
                      lastLoadingDoc = candidate;
                      lastLoadingTime = candidateTime;
                    } else if (candidateTime != null &&
                        candidateTime.compareTo(lastLoadingTime) > 0) {
                      // Strictly newer candidate replaces the current pick.
                      lastLoadingDoc = candidate;
                      lastLoadingTime = candidateTime;
                    }
                  }
                  await lastLoadingDoc!.reference.update({'endMeter': endMeterValue});
                }

                // Day-end summary row — just the meter reading and when it
                // was taken, not a rebuild of any single task's full detail
                // row (those already went out when each task was
                // paused/completed). Column order matches the existing
                // 17-column Supervisor_Loads/Plant_Loads header; every slot
                // other than these six stays blank.
                final row = [
                  GoogleSheetsService.formatDate(DateTime.now()),
                  widget.machineName,
                  widget.siteName,
                  widget.supervisorName,
                  '',
                  '',
                  '',
                  '',
                  '',
                  '',
                  endMeterValue.toString(),
                  '',
                  '',
                  GoogleSheetsService.formatTime(Timestamp.now()),
                  '',
                  '',
                  '',
                ];

                GoogleSheetsService.sendRow(sheetName: 'Supervisor_Loads', row: row);

                final siteDoc = await FirebaseFirestore.instance
                    .collection('sites')
                    .doc(widget.siteId)
                    .get();
                if (siteDoc.data()?['isPlantSite'] == true) {
                  GoogleSheetsService.sendRow(sheetName: 'Plant_Loads', row: row);
                }

                if (context.mounted) {
                  // Close dialog and go back to supervisor home in one atomic
                  // call — two sequential pop()s on the same Navigator race
                  // with the first pop's in-flight rebuild and hit the
                  // '!_debugLocked' assertion.
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to end day: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            child: const Text('END DAY', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWideWeb = kIsWeb && MediaQuery.of(context).size.width > 700;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => SupervisorScreen(name: widget.supervisorName),
                ),
              );
            }
          },
        ),
        title: Text(widget.machineName),
        backgroundColor: Colors.orange[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SupervisorHistoryScreen(sessionId: widget.sessionId),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.orange[50],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Site: ${widget.siteName}  •  Supervisor: ${widget.supervisorName}',
                  style: const TextStyle(fontSize: 13),
                ),
                if (widget.verificationCode != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.vpn_key, size: 16, color: Colors.orange),
                      const SizedBox(width: 6),
                      const Text('Driver Code: ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange[800],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.verificationCode!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 2),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (isWideWeb)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _showNewWorkDialog,
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text('NEW WORK', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _recordsRef.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No work started yet.\nTap "+ NEW WORK" to begin.',
                        textAlign: TextAlign.center),
                  );
                }

                final records = snapshot.data!.docs;

                final list = ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final doc = records[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isRunning = data['status'] == 'running';
                    final elapsed = _liveElapsedSeconds(data);

                    return _WebStaggeredFadeIn(
                      index: index,
                      child: _WebHoverCard(
                        child: Card(
                      color: isRunning ? Colors.green[50] : Colors.white,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isRunning ? Colors.green : Colors.grey[300]!,
                          width: isRunning ? 1.5 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  data['category'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isRunning ? Colors.green : Colors.grey[400],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isRunning ? 'RUNNING' : 'PAUSED',
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LiveTimerText(
                              totalDurationSeconds: (data['totalDurationSeconds'] ?? 0) as int,
                              isRunning: isRunning,
                              lastResumedAt: (data['lastResumedAt'] as Timestamp?)?.toDate(),
                            ),
                            if (data['truckNumber'] != null) ...[
                              const SizedBox(height: 6),
                              Text('Truck: ${data['truckNumber']} • Bill: ${data['billNumber']}',
                                  style: const TextStyle(fontSize: 13)),
                              Text(
                                  'To: ${data['unloadingSiteName']} • ${data['distanceKm']} KM',
                                  style: const TextStyle(fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(
                                  'Start Meter: ${data['startMeter'] ?? "-"}'
                                  '${data['isCompleted'] == true ? "  •  End Meter: ${data['endMeter'] ?? "-"}" : ""}',
                                  style: const TextStyle(fontSize: 13)),
                              if (data['isCompleted'] == true &&
                                  data['startMeter'] != null &&
                                  data['endMeter'] != null)
                                Text(
                                    'Meter Run: ${((data['endMeter'] as num) - (data['startMeter'] as num)).toStringAsFixed(1)}',
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue)),
                              Text(
                                  'Started: ${_formatTime(data['loadStartedAt'])}'
                                  '${data['loadCompletedAt'] != null ? "  •  Completed: ${_formatTime(data['loadCompletedAt'])}" : ""}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                            const SizedBox(height: 8),
                            if (data['isCompleted'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('LOAD COMPLETED',
                                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                              )
                            else if (!isRunning)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _resumeRecord(doc.id),
                                      icon: const Icon(Icons.play_arrow),
                                      label: const Text('RESUME'),
                                    ),
                                  ),
                                  if (data['isLoadingCategory'] == true) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _completeLoadingRecord(doc.id),
                                        icon: const Icon(Icons.check, color: Colors.white),
                                        label: const Text('COMPLETE', style: TextStyle(color: Colors.white)),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            else if (isRunning)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _pauseRunningRecord(),
                                      icon: const Icon(Icons.pause),
                                      label: const Text('PAUSE'),
                                    ),
                                  ),
                                  if (data['isLoadingCategory'] == true) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _completeLoadingRecord(doc.id),
                                        icon: const Icon(Icons.check, color: Colors.white),
                                        label: const Text('COMPLETE', style: TextStyle(color: Colors.white)),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                          ],
                        ),
                      ),
                        ),
                      ),
                    );
                  },
                );

                if (!isWideWeb) return list;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: list,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isWideWeb
          ? null
          : FloatingActionButton.extended(
              onPressed: _showNewWorkDialog,
              backgroundColor: Colors.orange[800],
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('NEW WORK', style: TextStyle(color: Colors.white)),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _showEndDayDialog,
              icon: const Icon(Icons.flag, color: Colors.white),
              label: const Text('END DAY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- NEW WORK DIALOG ----------------
class NewWorkDialog extends StatefulWidget {
  final List<String> loadingCategories;
  final List<String> otherCategories;
  final String currentSiteId;
  final Function(
      String category,
      String? truckNumber,
      String? billNumber,
      String? unloadingSiteName,
      double? distanceKm,
      double? startMeter,
      String? truckDriverName,
      String? cubeCount,
      String? machineOperatorName) onSubmit;

  const NewWorkDialog({
    super.key,
    required this.loadingCategories,
    required this.otherCategories,
    required this.currentSiteId,
    required this.onSubmit,
  });

  @override
  State<NewWorkDialog> createState() => _NewWorkDialogState();
}

class _NewWorkDialogState extends State<NewWorkDialog> {
  String? _selectedCategory;
  String? _selectedUnloadingSiteId;
  String? _selectedUnloadingSiteName;
  String? _selectedTruckNumber;
  final _truckDriverController = TextEditingController();
  final _cubeController = TextEditingController();
  String? _selectedOperatorUid;
  String? _selectedOperatorName;
  final _billNumberController = TextEditingController();
  final _distanceController = TextEditingController();
  bool _isCurrentSitePlantSite = false;
  String _errorText = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentSitePlantFlag();
  }

  Future<void> _loadCurrentSitePlantFlag() async {
    if (widget.currentSiteId.isEmpty) return;
    final doc =
        await FirebaseFirestore.instance.collection('sites').doc(widget.currentSiteId).get();
    if (!mounted) return;
    setState(() => _isCurrentSitePlantSite = doc.data()?['isPlantSite'] == true);
  }

  // Same search-bottom-sheet pattern as the Working Site picker, but with
  // one addition: since a Plant Site's loads can go to unregistered
  // destinations, typing a name with no exact match surfaces a "use as new
  // site" option instead of restricting selection to the registered list.
  Future<void> _showUnloadingSitePicker() async {
    final selected = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        String searchText = '';
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.75,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search or type a new site name',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (val) {
                          debugPrint('[UNLOADPICKER] onChanged val="$val"');
                          setSheetState(() => searchText = val);
                        },
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('sites').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final trimmedSearch = searchText.trim();
                          final filtered = snapshot.data!.docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            if (data['canBeUnloadingSite'] == false) return false;
                            final name = (data['name'] ?? '').toString();
                            return name.toLowerCase().contains(trimmedSearch.toLowerCase());
                          }).toList();
                          final hasExactMatch = filtered.any((doc) =>
                              ((doc.data() as Map<String, dynamic>)['name'] ?? '')
                                  .toString()
                                  .toLowerCase() ==
                              trimmedSearch.toLowerCase());
                          debugPrint('[UNLOADPICKER] build: searchText="$searchText" '
                              'trimmedSearch="$trimmedSearch" filtered=${filtered.length} '
                              'hasExactMatch=$hasExactMatch '
                              'showAddNew=${trimmedSearch.isNotEmpty && !hasExactMatch}');

                          return ListView(
                            children: [
                              if (trimmedSearch.isNotEmpty && !hasExactMatch)
                                ListTile(
                                  leading: const Icon(Icons.add_circle, color: AppTheme.accent),
                                  title: Text("Use '$trimmedSearch' as new site"),
                                  onTap: () {
                                    debugPrint(
                                        '[UNLOADPICKER] add-new tapped, name="$trimmedSearch"');
                                    Navigator.pop(sheetContext, {
                                      'id': null,
                                      'name': trimmedSearch,
                                    });
                                  },
                                ),
                              for (final doc in filtered)
                                Builder(builder: (context) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  return ListTile(
                                    leading: const Icon(Icons.location_on, color: Colors.teal),
                                    title: Text(data['name'] ?? ''),
                                    subtitle: Text(data['location'] ?? ''),
                                    onTap: () => Navigator.pop(sheetContext, {
                                      'id': doc.id,
                                      'name': (data['name'] ?? '').toString(),
                                    }),
                                  );
                                }),
                              if (filtered.isEmpty && trimmedSearch.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('No sites yet — start typing to add one.'),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    debugPrint('[UNLOADPICKER] sheet closed, selected=$selected');
    if (selected != null) {
      setState(() {
        _selectedUnloadingSiteId = selected['id'];
        _selectedUnloadingSiteName = selected['name'];
      });
      debugPrint('[UNLOADPICKER] set _selectedUnloadingSiteName=$_selectedUnloadingSiteName');
    }
  }

  bool get _isLoadingCategory =>
      _selectedCategory != null && widget.loadingCategories.contains(_selectedCategory);

  void _handleSubmit() {
    if (_selectedCategory == null) {
      setState(() => _errorText = 'Please select a work category.');
      return;
    }

    if (_isLoadingCategory) {
      if (_selectedTruckNumber == null || _selectedTruckNumber!.trim().isEmpty) {
        setState(() => _errorText = 'Please select a truck.');
        return;
      }
      if (_billNumberController.text.trim().isEmpty) {
        setState(() => _errorText = 'Bill Number is required for loading work.');
        return;
      }
      final unloadingSiteName = _selectedUnloadingSiteName?.trim();
      if (unloadingSiteName == null || unloadingSiteName.isEmpty) {
        setState(() => _errorText = 'Please select Unloading Site.');
        return;
      }
      if (_distanceController.text.trim().isEmpty) {
        setState(() => _errorText = 'Distance (KM) is required.');
        return;
      }

      widget.onSubmit(
        _selectedCategory!,
        _selectedTruckNumber!.trim(),
        _billNumberController.text.trim(),
        unloadingSiteName,
        double.tryParse(_distanceController.text.trim()),
        null,
        _truckDriverController.text.trim().isEmpty ? null : _truckDriverController.text.trim(),
        _cubeController.text.trim().isEmpty ? null : _cubeController.text.trim(),
        _selectedOperatorName,
      );
    } else {
      widget.onSubmit(_selectedCategory!, null, null, null, null, null, null, null, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Start New Work'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Work Category', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: [
                ...widget.loadingCategories.map(
                  (c) => DropdownMenuItem(value: c, child: Text('$c 🚛')),
                ),
                ...widget.otherCategories.map(
                  (c) => DropdownMenuItem(value: c, child: Text(c)),
                ),
              ],
              onChanged: (val) => setState(() {
                _selectedCategory = val;
                _errorText = '';
              }),
            ),
            if (_isLoadingCategory) ...[
              const SizedBox(height: 16),
              const Text('Select Truck', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('trucks').snapshots(),
                builder: (context, snapshot) {
                  final Set<String> truckNumbers = {};
                  if (snapshot.hasData) {
                    for (final doc in snapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final number = data['truckNumber'];
                      if (number != null && number.toString().isNotEmpty) {
                        truckNumbers.add(number.toString());
                      }
                    }
                  }
                  return Autocomplete<String>(
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                      return truckNumbers.where((number) => number
                          .toLowerCase()
                          .contains(textEditingValue.text.toLowerCase()));
                    },
                    onSelected: (selection) {
                      _selectedTruckNumber = selection;
                    },
                    fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                      controller.text = _selectedTruckNumber ?? '';
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: (val) => _selectedTruckNumber = val,
                        decoration: InputDecoration(
                          hintText: 'Enter or choose truck number',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _billNumberController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Bill Number *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Unloading Site *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('sites').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  final sites = snapshot.data!.docs;

                  // The current working site is a Plant Site — loads from a
                  // plant can go to many different unloading destinations,
                  // so the picker allows typing a brand-new site name
                  // instead of restricting to the registered list.
                  if (_isCurrentSitePlantSite) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _showUnloadingSitePicker,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          _selectedUnloadingSiteName ?? 'Search or type unloading site name',
                          style: TextStyle(
                            color: _selectedUnloadingSiteName == null
                                ? Colors.grey[600]
                                : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  }

                  return DropdownButtonFormField<String>(
                    initialValue: _selectedUnloadingSiteId,
                    decoration: InputDecoration(
                      hintText: 'Choose unloading site',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: sites.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text(data['name'] ?? ''),
                      );
                    }).toList(),
                    onChanged: (val) {
                      final selected = sites.firstWhere((d) => d.id == val);
                      final data = selected.data() as Map<String, dynamic>;
                      setState(() {
                        _selectedUnloadingSiteId = val;
                        _selectedUnloadingSiteName = data['name'];
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _distanceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Distance (KM) *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance
                    .collection('daily_sessions')
                    .doc('_dummy_')
                    .collection('work_records')
                    .limit(1)
                    .get(),
                builder: (context, _) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collectionGroup('work_records')
                        .where('truckDriverName', isNotEqualTo: null)
                        .limit(50)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final Set<String> pastNames = {};
                      if (snapshot.hasData) {
                        for (final doc in snapshot.data!.docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          final name = data['truckDriverName'];
                          if (name != null && name.toString().isNotEmpty) {
                            pastNames.add(name.toString());
                          }
                        }
                      }
                      return Autocomplete<String>(
                        optionsBuilder: (textEditingValue) {
                          if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                          return pastNames.where((name) => name
                              .toLowerCase()
                              .contains(textEditingValue.text.toLowerCase()));
                        },
                        onSelected: (selection) {
                          _truckDriverController.text = selection;
                        },
                        fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                          controller.text = _truckDriverController.text;
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            onChanged: (val) => _truckDriverController.text = val,
                            decoration: InputDecoration(
                              labelText: 'Truck Driver Name',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cubeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Cube (Quantity)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Machine Operator', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('canOperateMachine', isEqualTo: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  final operators = snapshot.data!.docs;
                  if (operators.isEmpty) {
                    return const Text('No operators registered.',
                        style: TextStyle(color: Colors.grey, fontSize: 12));
                  }
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedOperatorUid,
                    decoration: InputDecoration(
                      hintText: 'Choose operator',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: operators.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem<String>(
                          value: doc.id, child: Text(data['name'] ?? ''));
                    }).toList(),
                    onChanged: (val) {
                      final selected = operators.firstWhere((d) => d.id == val);
                      final data = selected.data() as Map<String, dynamic>;
                      setState(() {
                        _selectedOperatorUid = val;
                        _selectedOperatorName = data['name'];
                      });
                    },
                  );
                },
              ),
            ],
            if (_errorText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_errorText, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _handleSubmit,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
          child: const Text('START', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
// ---------------- LIVE TIMER TEXT (isolated rebuild) ----------------
class LiveTimerText extends StatefulWidget {
  final int totalDurationSeconds;
  final bool isRunning;
  final DateTime? lastResumedAt;

  const LiveTimerText({
    super.key,
    required this.totalDurationSeconds,
    required this.isRunning,
    required this.lastResumedAt,
  });

  @override
  State<LiveTimerText> createState() => _LiveTimerTextState();
}

class _LiveTimerTextState extends State<LiveTimerText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.isRunning) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant LiveTimerText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _timer?.cancel();
    if (widget.isRunning) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    int elapsed = widget.totalDurationSeconds;
    if (widget.isRunning && widget.lastResumedAt != null) {
      elapsed += DateTime.now().difference(widget.lastResumedAt!).inSeconds;
    }

    return Text(
      _formatDuration(elapsed),
      style: const TextStyle(
          fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
    );
  }
}
// ---------------- DRIVER: TYPE SELECT (Trucks / Machines) ----------------
class DriverTypeScreen extends StatefulWidget {
  final String name;
  const DriverTypeScreen({super.key, required this.name});

  @override
  State<DriverTypeScreen> createState() => _DriverTypeScreenState();
}

class _DriverTypeScreenState extends State<DriverTypeScreen> {
  bool _checkingActiveSession = true;

  @override
  void initState() {
    super.initState();
    _checkForActiveSession();
  }

  Future<void> _checkForActiveSession() async {
    try {
      final today = DateTime.now();
      final dateString =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      final existing = await FirebaseFirestore.instance
          .collection('driver_sessions')
          .where('driverUid', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .where('date', isEqualTo: dateString)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty && mounted) {
        final data = existing.docs.first.data();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DriverWorkAreaScreen(
              sessionId: existing.docs.first.id,
              machineName: data['machineName'] ?? '',
              machineType: data['machineType'] ?? '',
              siteName: data['siteName'] ?? '',
              driverName: widget.name,
            ),
          ),
        );
        return;
      }
    } catch (e) {
      // Offline or error — fall through to normal selection screen
    }
    if (mounted) setState(() => _checkingActiveSession = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingActiveSession) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
          child: const Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Welcome, ${widget.name}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('What are you operating today?',
                          style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.8))),
                      const SizedBox(height: 20),
                      GradientButton(
                        label: '1. Trucks',
                        icon: Icons.local_shipping,
                        height: 90,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => TruckTypeScreen(name: widget.name)),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      GradientButton(
                        label: '2. Machines',
                        icon: Icons.precision_manufacturing,
                        height: 90,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => DriverMachineTypeScreen(name: widget.name)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- DRIVER: MACHINE TYPE (200 / 70 / Loader) ----------------
class DriverMachineTypeScreen extends StatelessWidget {
  final String name;
  const DriverMachineTypeScreen({super.key, required this.name});

  static const Map<String, List<String>> machineTypeTasks = {
    '200 Machine': [
      'Sand Loading',
      'Sand Washing',
      'Soil Leveling',
      'Travel & Road Cleaning',
      'Mud & Stone Removing',
      'Other',
    ],
    '70 Machine': [
      'Soil Cutting',
      'Plant Loading',
      'Road Cleaning',
      'Other',
    ],
    'Loader': [
      'Soil Leveling & Moving',
      'Road Cleaning',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final types = machineTypeTasks.keys.toList();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => DriverTypeScreen(name: name)),
                          );
                        }
                      },
                    ),
                    const Text('Select Machine Type',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: types.map((type) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: GradientButton(
                          label: type,
                          height: 80,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DriverMachineSelectScreen(
                                  name: name,
                                  machineType: type,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- DRIVER: MACHINE SELECT (based on type) ----------------
class DriverMachineSelectScreen extends StatelessWidget {
  final String name;
  final String machineType;
  const DriverMachineSelectScreen({super.key, required this.name, required this.machineType});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => DriverTypeScreen(name: name)),
                          );
                        }
                      },
                    ),
                    Text(machineType,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('machines')
                      .where('type', isEqualTo: machineType)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final machines = snapshot.data!.docs;
                    if (machines.isEmpty) {
                      return const Center(
                          child: Text('No machines registered for this type.',
                              style: TextStyle(color: Colors.white)));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: machines.length,
                      itemBuilder: (context, index) {
                        final data = machines[index].data() as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DashboardMenuCard(
                            icon: Icons.precision_manufacturing,
                            title: data['name'] ?? '',
                            subtitle: data['number'] ?? '',
                            color: AppTheme.primaryMid,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DriverSiteSelectScreen(
                                    name: name,
                                    machineType: machineType,
                                    machineId: machines[index].id,
                                    machineName: data['name'] ?? '',
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- DRIVER: SITE SELECT + SUBMIT ----------------
class DriverSiteSelectScreen extends StatefulWidget {
  final String name;
  final String machineType;
  final String machineId;
  final String machineName;

  const DriverSiteSelectScreen({
    super.key,
    required this.name,
    required this.machineType,
    required this.machineId,
    required this.machineName,
  });

  @override
  State<DriverSiteSelectScreen> createState() => _DriverSiteSelectScreenState();
}

class _DriverSiteSelectScreenState extends State<DriverSiteSelectScreen> {
  String? _selectedSiteId;
  String? _selectedSiteName;
  final _codeController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submit() async {
    if (_selectedSiteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a site.')),
      );
      return;
    }

    if (_codeController.text.trim().length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 4-digit supervisor code.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final today = DateTime.now();
      final dateString =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      // Validate the supervisor code against an active session on this site today
      final supervisorMatch = await FirebaseFirestore.instance
          .collection('daily_sessions')
          .where('siteId', isEqualTo: _selectedSiteId)
          .where('date', isEqualTo: dateString)
          .where('status', isEqualTo: 'active')
          .where('verificationCode', isEqualTo: _codeController.text.trim())
          .limit(1)
          .get();

      if (supervisorMatch.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid code. Check with your supervisor.')),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      final existing = await FirebaseFirestore.instance
          .collection('driver_sessions')
          .where('machineId', isEqualTo: widget.machineId)
          .where('date', isEqualTo: dateString)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      String sessionId;

      if (existing.docs.isNotEmpty) {
        sessionId = existing.docs.first.id;
      } else {
        final docRef = await FirebaseFirestore.instance.collection('driver_sessions').add({
          'driverUid': FirebaseAuth.instance.currentUser!.uid,
          'driverName': widget.name,
          'machineId': widget.machineId,
          'machineName': widget.machineName,
          'machineType': widget.machineType,
          'siteId': _selectedSiteId,
          'siteName': _selectedSiteName,
          'supervisorSessionId': supervisorMatch.docs.first.id,
          'date': dateString,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        });
        sessionId = docRef.id;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriverWorkAreaScreen(
              sessionId: sessionId,
              machineName: widget.machineName,
              machineType: widget.machineType,
              siteName: _selectedSiteName ?? '',
              driverName: widget.name,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => DriverTypeScreen(name: widget.name)),
                          );
                        }
                      },
                    ),
                    Text(widget.machineName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Select Working Site',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 8),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('sites').snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const CircularProgressIndicator(color: Colors.white);
                            }
                            final sites = snapshot.data!.docs;
                            return DropdownButtonFormField<String>(
                              initialValue: _selectedSiteId,
                              dropdownColor: AppTheme.primaryMid,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Choose a site',
                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                                prefixIcon:
                                    Icon(Icons.location_on, color: Colors.white.withOpacity(0.7)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.accent),
                                ),
                              ),
                              items: sites.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return DropdownMenuItem<String>(
                                    value: doc.id, child: Text(data['name'] ?? ''));
                              }).toList(),
                              onChanged: (val) {
                                final selected = sites.firstWhere((d) => d.id == val);
                                final data = selected.data() as Map<String, dynamic>;
                                setState(() {
                                  _selectedSiteId = val;
                                  _selectedSiteName = data['name'];
                                });
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        const Text('Supervisor Code',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20, letterSpacing: 6),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '••••',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                            prefixIcon: Icon(Icons.vpn_key, color: Colors.white.withOpacity(0.7)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.accent),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Ask your supervisor for today\'s 4-digit code',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _isLoading
                            ? const Center(child: CircularProgressIndicator(color: Colors.white))
                            : GradientButton(
                                label: 'SUBMIT',
                                icon: Icons.check,
                                onTap: _submit,
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- DRIVER: WORK AREA ----------------
class DriverWorkAreaScreen extends StatefulWidget {
  final String sessionId;
  final String machineName;
  final String machineType;
  final String siteName;
  final String driverName;

  const DriverWorkAreaScreen({
    super.key,
    required this.sessionId,
    required this.machineName,
    required this.machineType,
    required this.siteName,
    required this.driverName,
  });

  @override
  State<DriverWorkAreaScreen> createState() => _DriverWorkAreaScreenState();
}

class _DriverWorkAreaScreenState extends State<DriverWorkAreaScreen> {
  double? _startMeter;

  CollectionReference get _recordsRef => FirebaseFirestore.instance
      .collection('driver_sessions')
      .doc(widget.sessionId)
      .collection('work_records');

  List<String> get _tasks =>
      DriverMachineTypeScreen.machineTypeTasks[widget.machineType] ?? [];

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _pauseRunningRecord() async {
    final runningSnap = await _recordsRef.where('status', isEqualTo: 'running').get();
    for (final doc in runningSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final lastResumedAt = (data['lastResumedAt'] as Timestamp?)?.toDate();
      final currentTotal = (data['totalDurationSeconds'] ?? 0) as int;
      int addedSeconds = 0;
      if (lastResumedAt != null) {
        addedSeconds = DateTime.now().difference(lastResumedAt).inSeconds;
      }
      final newTotal = currentTotal + addedSeconds;

      await doc.reference.update({
        'status': 'paused',
        'totalDurationSeconds': newTotal,
        'lastResumedAt': null,
      });

      // Sync this task's accumulated time to Google Sheets
      GoogleSheetsService.sendRow(
        sheetName: 'Machine_Tasks',
        row: [
          GoogleSheetsService.formatDate(DateTime.now()),
          widget.machineName,
          widget.machineType,
          widget.siteName,
          widget.driverName,
          data['task'] ?? '',
          _formatDuration(newTotal),
          GoogleSheetsService.formatTime(Timestamp.now()),
          _startMeter?.toString() ?? '',
          data['truckNumber'] ?? '',
        ],
      );
    }
  }

  bool _isLoadingCategory(String category) => category.toLowerCase().contains('loading');

  Future<void> _startTask(String taskName) async {
    if (_startMeter == null) {
      final meter = await _askStartMeter();
      if (meter == null) return;
      setState(() => _startMeter = meter);
    }

    final isLoading = _isLoadingCategory(taskName);
    String? truckNumber;
    if (isLoading) {
      // Always a fresh prompt — the previously selected truck is never
      // reused, since the driver may load a different truck each time.
      truckNumber = await _askTruckNumber();
      if (truckNumber == null) return;
    }

    await _pauseRunningRecord();

    final existingTaskSnap =
        await _recordsRef.where('task', isEqualTo: taskName).limit(1).get();

    if (existingTaskSnap.docs.isNotEmpty) {
      await existingTaskSnap.docs.first.reference.update({
        'status': 'running',
        'lastResumedAt': FieldValue.serverTimestamp(),
        if (isLoading) 'truckNumber': truckNumber,
      });
    } else {
      await _recordsRef.add({
        'task': taskName,
        'status': 'running',
        'totalDurationSeconds': 0,
        'lastResumedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        if (isLoading) 'truckNumber': truckNumber,
      });
    }
  }

  Future<String?> _askTruckNumber() async {
    String? selectedTruckId;
    String? selectedTruckNumber;
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Select Truck'),
          content: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('trucks').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 60,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final trucks = snapshot.data!.docs;
              if (trucks.isEmpty) {
                return const Text('No trucks registered. Contact Admin.',
                    style: TextStyle(color: Colors.red, fontSize: 13));
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedTruckId,
                    decoration: InputDecoration(
                      hintText: 'Choose truck',
                      prefixIcon: const Icon(Icons.local_shipping),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: trucks.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text(data['truckNumber'] ?? ''),
                      );
                    }).toList(),
                    onChanged: (val) {
                      final selected = trucks.firstWhere((d) => d.id == val);
                      final data = selected.data() as Map<String, dynamic>;
                      setDialogState(() {
                        selectedTruckId = val;
                        selectedTruckNumber = data['truckNumber'];
                        errorText = null;
                      });
                    },
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              );
            },
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                if (selectedTruckNumber == null) {
                  setDialogState(() => errorText = 'Please select a truck.');
                  return;
                }
                Navigator.pop(dialogContext, selectedTruckNumber);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[800]),
              child: const Text('CONFIRM', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<double?> _askStartMeter() async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Start Meter Reading'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. 1234.5',
            prefixIcon: const Icon(Icons.speed),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              if (val != null) Navigator.pop(context, val);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[800]),
            child: const Text('CONFIRM', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEndDayDialog() {
    final endMeterController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Day'),
        content: TextField(
          controller: endMeterController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'End Meter Reading',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (endMeterController.text.trim().isEmpty) return;
              await _pauseRunningRecord();
              await FirebaseFirestore.instance
                  .collection('driver_sessions')
                  .doc(widget.sessionId)
                  .update({
                'startMeter': _startMeter,
                'endMeter': double.tryParse(endMeterController.text.trim()) ?? 0,
                'status': 'completed',
                'completedAt': FieldValue.serverTimestamp(),
              });
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            child: const Text('END DAY', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverTypeScreen(name: widget.driverName),
                ),
              );
            }
          },
        ),
        title: Text(widget.machineName),
        backgroundColor: Colors.purple[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverHistoryScreen(sessionId: widget.sessionId),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.purple[50],
            child: Text(
              'Site: ${widget.siteName}  •  Driver: ${widget.driverName}',
              style: const TextStyle(fontSize: 13),
            ),
          ),

          // Active/paused task cards
          StreamBuilder<QuerySnapshot>(
            stream: _recordsRef.orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SizedBox.shrink();
              }
              final records = snapshot.data!.docs;

              return Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final doc = records[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isRunning = data['status'] == 'running';

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isRunning ? Colors.green[50] : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isRunning ? Colors.green : Colors.grey[300]!,
                          width: isRunning ? 1.6 : 1,
                        ),
                        boxShadow: isRunning
                            ? [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.25),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ]
                            : [],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          if (isRunning) const PulsingDot(),
                          if (isRunning) const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  data['task'] ?? '',
                                  style:
                                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                if (data['truckNumber'] != null)
                                  Text(
                                    'Truck: ${data['truckNumber']}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),
                          LiveTimerText(
                            totalDurationSeconds: (data['totalDurationSeconds'] ?? 0) as int,
                            isRunning: isRunning,
                            lastResumedAt: (data['lastResumedAt'] as Timestamp?)?.toDate(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.3,
                ),
                itemCount: _tasks.length,
                itemBuilder: (context, index) {
                  return TaskButton(
                    label: _tasks[index],
                    onTap: () => _startTask(_tasks[index]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _pauseRunningRecord,
                    icon: const Icon(Icons.pause),
                    label: const Text('PAUSE'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _showEndDayDialog,
                    icon: const Icon(Icons.flag, color: Colors.white),
                    label: const Text('END', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------- DRIVER HISTORY SCREEN ----------------
class DriverHistoryScreen extends StatelessWidget {
  final String sessionId;
  const DriverHistoryScreen({super.key, required this.sessionId});

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  int _liveElapsed(Map<String, dynamic> data) {
    int total = (data['totalDurationSeconds'] ?? 0) as int;
    if (data['status'] == 'running' && data['lastResumedAt'] != null) {
      final lastResumedAt = (data['lastResumedAt'] as Timestamp).toDate();
      total += DateTime.now().difference(lastResumedAt).inSeconds;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text("Today's History",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('driver_sessions')
                      .doc(sessionId)
                      .snapshots(),
                  builder: (context, sessionSnap) {
                    if (!sessionSnap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final sessionData = sessionSnap.data!.data() as Map<String, dynamic>?;

                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('driver_sessions')
                          .doc(sessionId)
                          .collection('work_records')
                          .orderBy('createdAt', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator(color: Colors.white));
                        }
                        final records = snapshot.data!.docs;

                        int totalSeconds = 0;
                        for (final doc in records) {
                          final data = doc.data() as Map<String, dynamic>;
                          totalSeconds += _liveElapsed(data);
                        }

                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GlassCard(
                                child: Column(
                                  children: [
                                    const Icon(Icons.timer, color: Colors.white, size: 32),
                                    const SizedBox(height: 8),
                                    Text(
                                      _formatDuration(totalSeconds),
                                      style: const TextStyle(
                                          fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    Text('Total Worked Today',
                                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                                    if (sessionData != null &&
                                        sessionData['startMeter'] != null) ...[
                                      const Divider(color: Colors.white24, height: 24),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: [
                                          Column(
                                            children: [
                                              Text('${sessionData['startMeter']}',
                                                  style: const TextStyle(
                                                      color: Colors.white, fontWeight: FontWeight.bold)),
                                              Text('Start Meter',
                                                  style: TextStyle(
                                                      color: Colors.white.withOpacity(0.6), fontSize: 11)),
                                            ],
                                          ),
                                          if (sessionData['endMeter'] != null)
                                            Column(
                                              children: [
                                                Text('${sessionData['endMeter']}',
                                                    style: const TextStyle(
                                                        color: Colors.white, fontWeight: FontWeight.bold)),
                                                Text('End Meter',
                                                    style: TextStyle(
                                                        color: Colors.white.withOpacity(0.6), fontSize: 11)),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text('Task Breakdown',
                                  style: TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                              const SizedBox(height: 12),
                              if (records.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  child: Text('No tasks recorded yet.',
                                      style: TextStyle(color: Colors.white.withOpacity(0.7))),
                                )
                              else
                                ...records.map((doc) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  final elapsed = _liveElapsed(data);
                                  final isRunning = data['status'] == 'running';

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: GlassCard(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        children: [
                                          if (isRunning) const PulsingDot(),
                                          if (isRunning) const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              data['task'] ?? '',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14),
                                            ),
                                          ),
                                          Text(
                                            _formatDuration(elapsed),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'monospace'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------- APP THEME (Central Design System) ----------------
class AppTheme {
  static const primaryDark = Color(0xFF1A1B4B);
  static const primaryMid = Color(0xFF3D2C8D);
  static const accent = Color(0xFF00D9C6);

  static const mainGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1B4B), Color(0xFF3D2C8D)],
  );

  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3D2C8D), Color(0xFF6B4CE6)],
  );

  static BoxShadow softShadow = BoxShadow(
    color: Colors.black.withOpacity(0.12),
    blurRadius: 16,
    offset: const Offset(0, 6),
  );
}

// ---------------- WEB APP SHELL (desktop sidebar layout, web only) ----------------
class WebSidebarItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const WebSidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

// Reusable shell that adds a fixed desktop sidebar around a screen's body
// content on wide web viewports. On mobile (or a narrow web window) it's a
// pure pass-through — returns child as-is, no wrapper — so it can never
// affect the mobile app layout.
class WebAppShell extends StatelessWidget {
  static const double sidebarWidth = 250;
  static const double desktopBreakpoint = 900;

  final String appName;
  final List<WebSidebarItem> menuItems;
  final VoidCallback onLogout;
  final Widget child;

  const WebAppShell({
    super.key,
    required this.appName,
    required this.menuItems,
    required this.onLogout,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktopWeb =
        kIsWeb && MediaQuery.of(context).size.width > desktopBreakpoint;
    if (!isDesktopWeb) {
      return child;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: sidebarWidth,
          decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'N',
                          style: TextStyle(
                            color: AppTheme.primaryDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          appName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: menuItems
                        .map((item) => _WebSidebarTile(
                              icon: item.icon,
                              label: item.label,
                              onTap: item.onTap,
                            ))
                        .toList(),
                  ),
                ),
                const Divider(color: Colors.white24, height: 1),
                _WebSidebarTile(icon: Icons.logout, label: 'Logout', onTap: onLogout),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _WebSidebarTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _WebSidebarTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_WebSidebarTile> createState() => _WebSidebarTileState();
}

class _WebSidebarTileState extends State<_WebSidebarTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _hovering ? Colors.white.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Staggered fade-in + slide-up entrance for dashboard cards, web only. On
// mobile it's a pure pass-through (no timer, no extra animation) so it can
// never affect the mobile app.
class _WebStaggeredFadeIn extends StatefulWidget {
  final int index;
  final Widget child;

  const _WebStaggeredFadeIn({required this.index, required this.child});

  @override
  State<_WebStaggeredFadeIn> createState() => _WebStaggeredFadeInState();
}

class _WebStaggeredFadeInState extends State<_WebStaggeredFadeIn> {
  bool _start = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      Future.delayed(Duration(milliseconds: 70 * widget.index), () {
        if (mounted) setState(() => _start = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: _start ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 16),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

// Generic hover scale + shadow wrapper for list-item cards, web only.
// Wraps any existing card widget without needing to touch its own
// decoration/elevation — mobile gets _hovering permanently false via the
// kIsWeb guard, so AnimatedScale/AnimatedContainer settle on unchanged
// static values and there is no visible or behavioral difference.
class _WebHoverCard extends StatefulWidget {
  final Widget child;

  const _WebHoverCard({required this.child});

  @override
  State<_WebHoverCard> createState() => _WebHoverCardState();
}

class _WebHoverCardState extends State<_WebHoverCard> {
  bool _hovering = false;

  void _setHover(bool value) {
    if (!kIsWeb) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      cursor: kIsWeb ? SystemMouseCursors.click : MouseCursor.defer,
      child: AnimatedScale(
        scale: _hovering ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _hovering
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.20),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------------- GRADIENT BUTTON (with press animation) ----------------
class GradientButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final Gradient gradient;
  final double height;

  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.gradient = AppTheme.cardGradient,
    this.height = 54,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (widget.gradient.colors.last).withOpacity(0.4),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
              ],
              Text(
                widget.label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- GLASS CARD (frosted glass style) ----------------
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: child,
    );
  }
}

// ---------------- DASHBOARD MENU CARD (icon + title, gradient) ----------------
class DashboardMenuCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const DashboardMenuCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<DashboardMenuCard> createState() => _DashboardMenuCardState();
}

class _DashboardMenuCardState extends State<DashboardMenuCard> {
  double _scale = 1.0;
  bool _hovering = false;

  // Web-only hover scale/shadow — mobile has no cursor, so this never fires
  // there, but the kIsWeb guard keeps it explicit and inert on mobile too.
  void _setHover(bool value) {
    if (!kIsWeb) return;
    setState(() {
      _hovering = value;
      _scale = value ? 1.03 : 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      cursor: kIsWeb ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _scale = 0.97),
        onTapUp: (_) {
          setState(() => _scale = _hovering ? 1.03 : 1.0);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _scale = _hovering ? 1.03 : 1.0),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                _hovering
                    ? BoxShadow(
                        color: Colors.black.withOpacity(0.20),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      )
                    : AppTheme.softShadow,
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [widget.color.withOpacity(0.8), widget.color],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(widget.subtitle,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- TASK BUTTON (Driver work area, tap animation) ----------------
class TaskButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const TaskButton({super.key, required this.label, required this.onTap, this.color});

  @override
  State<TaskButton> createState() => _TaskButtonState();
}

class _TaskButtonState extends State<TaskButton> {
  double _scale = 1.0;

  static const List<Color> _palette = [
    Color(0xFFEF6C57), // coral
    Color(0xFF3D9DE0), // sky blue
    Color(0xFF4CAF7D), // green
    Color(0xFFE0A93D), // amber
    Color(0xFF9B6BE0), // purple
    Color(0xFFE05C97), // pink
    Color(0xFF3DBFC4), // teal
    Color(0xFF7D8CE0), // indigo
  ];

  Color _colorForLabel(String label) {
    final index = label.hashCode.abs() % _palette.length;
    return _palette[index];
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.color ?? _colorForLabel(widget.label);

    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.94),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, baseColor.withOpacity(0.75)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: baseColor.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(10),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ),
    );
  }
}

// ---------------- PULSING DOT (live indicator) ----------------
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
      ),
    );
  }
}

// ---------------- FADE SLIDE PAGE ROUTE (screen transitions) ----------------
class FadeSlideRoute extends PageRouteBuilder {
  final Widget page;
  FadeSlideRoute({required this.page})
      : super(
          transitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(fade);
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(position: slide, child: child),
            );
          },
        );
}

// Web gets the fade+slide transition; mobile keeps its native platform
// page transition (MaterialPageRoute) untouched.
void pushWebAware(BuildContext context, Widget page) {
  Navigator.push(
    context,
    kIsWeb ? FadeSlideRoute(page: page) : MaterialPageRoute(builder: (_) => page),
  );
}

// ---------------- SUPERVISOR HISTORY SCREEN ----------------
class SupervisorHistoryScreen extends StatelessWidget {
  final String sessionId;
  const SupervisorHistoryScreen({super.key, required this.sessionId});

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  int _liveElapsed(Map<String, dynamic> data) {
    int total = (data['totalDurationSeconds'] ?? 0) as int;
    if (data['status'] == 'running' && data['lastResumedAt'] != null) {
      final lastResumedAt = (data['lastResumedAt'] as Timestamp).toDate();
      total += DateTime.now().difference(lastResumedAt).inSeconds;
    }
    return total;
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '-';
    final dt = ts.toDate();
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text("Today's History",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('daily_sessions')
                      .doc(sessionId)
                      .snapshots(),
                  builder: (context, sessionSnap) {
                    if (!sessionSnap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final sessionData = sessionSnap.data!.data() as Map<String, dynamic>?;

                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('daily_sessions')
                          .doc(sessionId)
                          .collection('work_records')
                          .orderBy('createdAt', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator(color: Colors.white));
                        }
                        final records = snapshot.data!.docs;

                        int totalSeconds = 0;
                        int completedLoads = 0;
                        for (final doc in records) {
                          final data = doc.data() as Map<String, dynamic>;
                          totalSeconds += _liveElapsed(data);
                          if (data['isCompleted'] == true) completedLoads++;
                        }

                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GlassCard(
                                child: Column(
                                  children: [
                                    const Icon(Icons.timer, color: Colors.white, size: 32),
                                    const SizedBox(height: 8),
                                    Text(
                                      _formatDuration(totalSeconds),
                                      style: const TextStyle(
                                          fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    Text('Total Worked Today',
                                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                                    if (sessionData != null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Started: ${_formatTime(sessionData['createdAt'] as Timestamp?)}'
                                        '${sessionData['completedAt'] != null ? "  •  Ended: ${_formatTime(sessionData['completedAt'] as Timestamp?)}" : ""}',
                                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                                      ),
                                    ],
                                    const Divider(color: Colors.white24, height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                                      children: [
                                        Column(
                                          children: [
                                            Text('$completedLoads',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 18)),
                                            Text('Loads Completed',
                                                style: TextStyle(
                                                    color: Colors.white.withOpacity(0.6), fontSize: 11)),
                                          ],
                                        ),
                                        if (sessionData != null && sessionData['startMeter'] != null)
                                          Column(
                                            children: [
                                              Text('${sessionData['startMeter']}',
                                                  style: const TextStyle(
                                                      color: Colors.white, fontWeight: FontWeight.bold)),
                                              Text('Start Meter',
                                                  style: TextStyle(
                                                      color: Colors.white.withOpacity(0.6), fontSize: 11)),
                                            ],
                                          ),
                                        if (sessionData != null && sessionData['endMeter'] != null)
                                          Column(
                                            children: [
                                              Text('${sessionData['endMeter']}',
                                                  style: const TextStyle(
                                                      color: Colors.white, fontWeight: FontWeight.bold)),
                                              Text('End Meter',
                                                  style: TextStyle(
                                                      color: Colors.white.withOpacity(0.6), fontSize: 11)),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text('Work Records',
                                  style: TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                              const SizedBox(height: 12),
                              if (records.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  child: Text('No work recorded yet.',
                                      style: TextStyle(color: Colors.white.withOpacity(0.7))),
                                )
                              else
                                ...records.map((doc) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  final elapsed = _liveElapsed(data);
                                  final isRunning = data['status'] == 'running';
                                  final isLoading = data['isLoadingCategory'] == true;

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: GlassCard(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              if (isRunning) const PulsingDot(),
                                              if (isRunning) const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  data['category'] ?? '',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14),
                                                ),
                                              ),
                                              Text(
                                                _formatDuration(elapsed),
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'monospace'),
                                              ),
                                            ],
                                          ),
                                          if (isLoading) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              'Truck: ${data['truckNumber'] ?? '-'} • Bill: ${data['billNumber'] ?? '-'}',
                                              style: TextStyle(
                                                  color: Colors.white.withOpacity(0.8), fontSize: 12),
                                            ),
                                            if (data['isCompleted'] == true)
                                              Text(
                                                'Meter: ${data['startMeter'] ?? "-"} → ${data['endMeter'] ?? "-"}  •  ${_formatTime(data['loadStartedAt'])} - ${_formatTime(data['loadCompletedAt'])}',
                                                style: TextStyle(
                                                    color: Colors.white.withOpacity(0.6), fontSize: 11),
                                              ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------- SITE HISTORY SCREEN (Owner) ----------------
class SiteHistoryScreen extends StatelessWidget {
  final String siteId;
  final String siteName;

  const SiteHistoryScreen({super.key, required this.siteId, required this.siteName});

  static const List<Color> _dayColors = [
    Color(0xFF3D9DE0),
    Color(0xFF4CAF7D),
    Color(0xFFE0A93D),
    Color(0xFF9B6BE0),
    Color(0xFFE05C97),
    Color(0xFF3DBFC4),
    Color(0xFFEF6C57),
    Color(0xFF7D8CE0),
  ];

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '-';
    final dt = ts.toDate();
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  String _formatDateHeader(String dateString) {
    final parts = dateString.split('-');
    if (parts.length != 3) return dateString;
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final today = DateTime.now();
    final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    if (dateString == todayStr) return 'Today';

    final yesterday = today.subtract(const Duration(days: 1));
    final yestStr = "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";
    if (dateString == yestStr) return 'Yesterday';

    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<int> _countLoadsForSession(String sessionId) async {
    final snap = await FirebaseFirestore.instance
        .collection('daily_sessions')
        .doc(sessionId)
        .collection('work_records')
        .where('isCompleted', isEqualTo: true)
        .get();
    return snap.docs.length;
  }

  Future<int> _totalSecondsForSession(String sessionId) async {
    final snap = await FirebaseFirestore.instance
        .collection('daily_sessions')
        .doc(sessionId)
        .collection('work_records')
        .get();
    int total = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      int seconds = (data['totalDurationSeconds'] ?? 0) as int;
      if (data['status'] == 'running' && data['lastResumedAt'] != null) {
        final lastResumedAt = (data['lastResumedAt'] as Timestamp).toDate();
        seconds += DateTime.now().difference(lastResumedAt).inSeconds;
      }
      total += seconds;
    }
    return total;
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  void _showForceCloseDialog(BuildContext context, String sessionId, dynamic startMeter) {
    final endMeterController = TextEditingController(
      text: startMeter != null ? startMeter.toString() : '',
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Force Close Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This session was left active (not properly ended). Enter the end meter reading to close it.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: endMeterController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'End Meter Reading',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final endMeter = double.tryParse(endMeterController.text.trim());
              if (endMeter == null) return;

              // Pause any running work_records under this session first
              final recordsRef = FirebaseFirestore.instance
                  .collection('daily_sessions')
                  .doc(sessionId)
                  .collection('work_records');
              final runningRecords =
                  await recordsRef.where('status', isEqualTo: 'running').get();
              for (final doc in runningRecords.docs) {
                final data = doc.data();
                final lastResumedAt = (data['lastResumedAt'] as Timestamp?)?.toDate();
                final currentTotal = (data['totalDurationSeconds'] ?? 0) as int;
                int addedSeconds = 0;
                if (lastResumedAt != null) {
                  addedSeconds = DateTime.now().difference(lastResumedAt).inSeconds;
                }
                await doc.reference.update({
                  'status': 'paused',
                  'totalDurationSeconds': currentTotal + addedSeconds,
                  'lastResumedAt': null,
                });
              }

              // Close the session itself
              await FirebaseFirestore.instance
                  .collection('daily_sessions')
                  .doc(sessionId)
                  .update({
                'endMeter': endMeter,
                'status': 'completed',
                'completedAt': FieldValue.serverTimestamp(),
                'forceClosedByOwner': true,
              });

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Session closed successfully.')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            child: const Text('FORCE CLOSE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showChangeSiteCapabilityDialog(
      BuildContext context, bool currentCanLoad, bool currentCanUnload) {
    bool canLoad = currentCanLoad;
    bool canUnload = currentCanUnload;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Change Site Capability'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Can be Loading Site'),
                value: canLoad,
                onChanged: (val) => setDialogState(() => canLoad = val ?? false),
              ),
              CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Can be Unloading Site'),
                value: canUnload,
                onChanged: (val) => setDialogState(() => canUnload = val ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance.collection('sites').doc(siteId).update({
                  'canBeLoadingSite': canLoad,
                  'canBeUnloadingSite': canUnload,
                });
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryMid),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(siteName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('sites').doc(siteId).snapshots(),
                  builder: (context, siteSnap) {
                    final siteData = siteSnap.data?.data() as Map<String, dynamic>?;
                    final canLoad = siteData?['canBeLoadingSite'] != false;
                    final canUnload = siteData?['canBeUnloadingSite'] != false;
                    return GlassCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(canLoad ? Icons.check_circle : Icons.cancel,
                                        color: canLoad ? Colors.greenAccent : Colors.redAccent,
                                        size: 16),
                                    const SizedBox(width: 6),
                                    const Text('Loading Capability',
                                        style: TextStyle(color: Colors.white, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(canUnload ? Icons.check_circle : Icons.cancel,
                                        color: canUnload ? Colors.greenAccent : Colors.redAccent,
                                        size: 16),
                                    const SizedBox(width: 6),
                                    const Text('Unloading Capability',
                                        style: TextStyle(color: Colors.white, fontSize: 13)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _showChangeSiteCapabilityDialog(context, canLoad, canUnload),
                            icon: const Icon(Icons.edit, size: 16, color: AppTheme.accent),
                            label:
                                const Text('Change', style: TextStyle(color: AppTheme.accent)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('daily_sessions')
                      .where('siteId', isEqualTo: siteId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Error: ${snapshot.error}',
                              style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final sessions = snapshot.data!.docs;
                    if (sessions.isEmpty) {
                      return const Center(
                        child: Text('No work history for this site yet.',
                            style: TextStyle(color: Colors.white)),
                      );
                    }

                    // Group sessions by date
                    final Map<String, List<QueryDocumentSnapshot>> grouped = {};
                    for (final doc in sessions) {
                      final data = doc.data() as Map<String, dynamic>;
                      final date = data['date'] ?? 'unknown';
                      grouped.putIfAbsent(date, () => []).add(doc);
                    }
                    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: sortedDates.length,
                      itemBuilder: (context, dateIndex) {
                        final date = sortedDates[dateIndex];
                        final dayColor = _dayColors[dateIndex % _dayColors.length];
                        final daySessions = grouped[date]!;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(color: dayColor, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatDateHeader(date),
                                    style: const TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ...daySessions.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final isActive = data['status'] == 'active';

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10, left: 18),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border(left: BorderSide(color: dayColor, width: 4)),
                                    ),
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                data['machineName'] ?? '',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14),
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: isActive
                                                  ? () => _showForceCloseDialog(
                                                      context, doc.id, data['startMeter'])
                                                  : null,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: isActive ? Colors.green : Colors.grey,
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      isActive ? 'ACTIVE' : 'DONE',
                                                      style: const TextStyle(color: Colors.white, fontSize: 10),
                                                    ),
                                                    if (isActive) ...[
                                                      const SizedBox(width: 4),
                                                      const Icon(Icons.edit, size: 11, color: Colors.white),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Supervisor: ${data['supervisorName'] ?? '-'}',
                                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                                        ),
                                        Text(
                                          'Started: ${_formatTime(data['createdAt'] as Timestamp?)}'
                                          '${data['completedAt'] != null ? "  •  Ended: ${_formatTime(data['completedAt'] as Timestamp?)}" : ""}',
                                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                                        ),
                                        if (data['startMeter'] != null) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.speed, size: 13, color: Colors.white.withOpacity(0.7)),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Start Meter: ${data['startMeter']}'
                                                '${data['endMeter'] != null ? "  •  End Meter: ${data['endMeter']}" : ""}',
                                                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        FutureBuilder<List<int>>(
                                          future: Future.wait([
                                            _countLoadsForSession(doc.id),
                                            _totalSecondsForSession(doc.id),
                                          ]),
                                          builder: (context, futureSnap) {
                                            if (!futureSnap.hasData) {
                                              return const SizedBox(
                                                height: 16,
                                                width: 16,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2, color: Colors.white),
                                              );
                                            }
                                            final loads = futureSnap.data![0];
                                            final seconds = futureSnap.data![1];
                                            return Row(
                                              children: [
                                                Icon(Icons.local_shipping,
                                                    size: 14, color: Colors.white.withOpacity(0.7)),
                                                const SizedBox(width: 4),
                                                Text('$loads loads',
                                                    style: TextStyle(
                                                        color: Colors.white.withOpacity(0.8), fontSize: 12)),
                                                const SizedBox(width: 16),
                                                Icon(Icons.timer,
                                                    size: 14, color: Colors.white.withOpacity(0.7)),
                                                const SizedBox(width: 4),
                                                Text(_formatDuration(seconds),
                                                    style: TextStyle(
                                                        color: Colors.white.withOpacity(0.8), fontSize: 12)),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------- ADMIN SITE LIST (navigates to shared SiteHistoryScreen) ----------------
class AdminSiteListScreen extends StatelessWidget {
  const AdminSiteListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text('Site History',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('sites').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final sites = snapshot.data!.docs;
                    if (sites.isEmpty) {
                      return const Center(
                        child: Text('No sites added yet.', style: TextStyle(color: Colors.white)),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: sites.length,
                      itemBuilder: (context, index) {
                        final data = sites[index].data() as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _WebStaggeredFadeIn(
                            index: index,
                            child: DashboardMenuCard(
                              icon: Icons.location_on,
                              title: data['name'] ?? '',
                              subtitle: data['location'] ?? '',
                              color: Colors.teal,
                              onTap: () {
                                pushWebAware(
                                  context,
                                  SiteHistoryScreen(
                                    siteId: sites[index].id,
                                    siteName: data['name'] ?? '',
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------- GOOGLE SHEETS SYNC SERVICE ----------------
class GoogleSheetsService {
  static const String _webAppUrl =
      'https://script.google.com/macros/s/AKfycbyDjLHlC7MuTeKw2gA6W-7Rlpj1a6aU17RWzHBLPI7B93bXAGOs99IzLpYpc4nd3AY/exec';

  static Future<void> sendRow({
    required String sheetName,
    required List<dynamic> row,
  }) async {
    try {
      // Content-Type must stay outside the CORS-safelisted set (text/plain,
      // not application/json) — Apps Script web apps don't answer the
      // OPTIONS preflight a JSON content-type forces, so on Flutter Web the
      // browser blocks the request before it ever reaches the script. The
      // Apps Script side reads the raw body text and JSON-decodes it itself,
      // so it doesn't care what the header says.
      await http.post(
        Uri.parse(_webAppUrl),
        headers: {'Content-Type': 'text/plain'},
        body: jsonEncode({
          'sheetName': sheetName,
          'row': row,
        }),
      );
    } catch (e) {
      // Silently fail - Sheets sync is a nice-to-have, shouldn't break the app
      debugPrint('Google Sheets sync error: $e');
    }
  }

  static String formatDate(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  static String formatTime(dynamic ts) {
    if (ts == null) return '-';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else {
      return '-';
    }
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
// ---------------- USER PROFILE SCREEN ----------------
class UserProfileScreen extends StatelessWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final String userRole;
  final String? photoBase64;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userRole,
    this.photoBase64,
  });

  static const List<Color> _dayColors = [
    Color(0xFF3D9DE0),
    Color(0xFF4CAF7D),
    Color(0xFFE0A93D),
    Color(0xFF9B6BE0),
    Color(0xFFE05C97),
    Color(0xFF3DBFC4),
    Color(0xFFEF6C57),
    Color(0xFF7D8CE0),
  ];

  String get _collectionName =>
      userRole == 'driver' ? 'driver_sessions' : 'daily_sessions';
  String get _uidField => userRole == 'driver' ? 'driverUid' : 'supervisorUid';

  String _formatTime(dynamic ts) {
    if (ts == null) return '-';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else {
      return '-';
    }
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  String _formatDateHeader(String dateString) {
    final parts = dateString.split('-');
    if (parts.length != 3) return dateString;
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final today = DateTime.now();
    final todayStr =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    if (dateString == todayStr) return 'Today';

    final yesterday = today.subtract(const Duration(days: 1));
    final yestStr =
        "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";
    if (dateString == yestStr) return 'Yesterday';

    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<int> _countLoadsForSession(String sessionId) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionName)
        .doc(sessionId)
        .collection('work_records')
        .get();
    if (userRole == 'driver') {
      return snap.docs.length; // count of tasks
    }
    return snap.docs.where((d) => (d.data())['isCompleted'] == true).length;
  }

  Future<int> _totalSecondsForSession(String sessionId) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionName)
        .doc(sessionId)
        .collection('work_records')
        .get();
    int total = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      int seconds = (data['totalDurationSeconds'] ?? 0) as int;
      if (data['status'] == 'running' && data['lastResumedAt'] != null) {
        final lastResumedAt = (data['lastResumedAt'] as Timestamp).toDate();
        seconds += DateTime.now().difference(lastResumedAt).inSeconds;
      }
      total += seconds;
    }
    return total;
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text('User Profile',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Profile header card
                      GlassCard(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 45,
                              backgroundColor: Colors.white.withOpacity(0.2),
                              backgroundImage: photoBase64 != null
                                  ? MemoryImage(base64Decode(photoBase64!))
                                  : null,
                              child: photoBase64 == null
                                  ? const Icon(Icons.person, size: 45, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Text(userName,
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                            const SizedBox(height: 4),
                            Text(userEmail,
                                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppTheme.accent),
                              ),
                              child: Text(
                                userRole.toUpperCase(),
                                style: const TextStyle(
                                    color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Work History',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      const SizedBox(height: 12),

                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection(_collectionName)
                            .where(_uidField, isEqualTo: userId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 30),
                              child: CircularProgressIndicator(color: Colors.white),
                            );
                          }
                          final sessions = snapshot.data!.docs;
                          if (sessions.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text('No work history yet.',
                                  style: TextStyle(color: Colors.white)),
                            );
                          }

                          final Map<String, List<QueryDocumentSnapshot>> grouped = {};
                          for (final doc in sessions) {
                            final data = doc.data() as Map<String, dynamic>;
                            final date = data['date'] ?? 'unknown';
                            grouped.putIfAbsent(date, () => []).add(doc);
                          }
                          final sortedDates = grouped.keys.toList()
                            ..sort((a, b) => b.compareTo(a));

                          return Column(
                            children: List.generate(sortedDates.length, (dateIndex) {
                              final date = sortedDates[dateIndex];
                              final dayColor = _dayColors[dateIndex % _dayColors.length];
                              final daySessions = grouped[date]!;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration:
                                              BoxDecoration(color: dayColor, shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatDateHeader(date),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    ...daySessions.map((doc) {
                                      final data = doc.data() as Map<String, dynamic>;
                                      final isActive = data['status'] == 'active';

                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 10, left: 18),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(14),
                                            border:
                                                Border(left: BorderSide(color: dayColor, width: 4)),
                                          ),
                                          padding: const EdgeInsets.all(14),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      '${data['machineName'] ?? ''} • ${data['siteName'] ?? ''}',
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: isActive ? Colors.green : Colors.grey,
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Text(
                                                      isActive ? 'ACTIVE' : 'DONE',
                                                      style: const TextStyle(
                                                          color: Colors.white, fontSize: 10),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Started: ${_formatTime(data['createdAt'])}'
                                                '${data['completedAt'] != null ? "  •  Ended: ${_formatTime(data['completedAt'])}" : ""}',
                                                style: TextStyle(
                                                    color: Colors.white.withOpacity(0.6), fontSize: 11),
                                              ),
                                              if (data['startMeter'] != null) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Start Meter: ${data['startMeter']}'
                                                  '${data['endMeter'] != null ? "  •  End Meter: ${data['endMeter']}" : ""}',
                                                  style: TextStyle(
                                                      color: Colors.white.withOpacity(0.7),
                                                      fontSize: 12),
                                                ),
                                              ],
                                              const SizedBox(height: 8),
                                              FutureBuilder<List<int>>(
                                                future: Future.wait([
                                                  _countLoadsForSession(doc.id),
                                                  _totalSecondsForSession(doc.id),
                                                ]),
                                                builder: (context, futureSnap) {
                                                  if (!futureSnap.hasData) {
                                                    return const SizedBox(
                                                      height: 16,
                                                      width: 16,
                                                      child: CircularProgressIndicator(
                                                          strokeWidth: 2, color: Colors.white),
                                                    );
                                                  }
                                                  final count = futureSnap.data![0];
                                                  final seconds = futureSnap.data![1];
                                                  return Row(
                                                    children: [
                                                      Icon(
                                                        userRole == 'driver'
                                                            ? Icons.checklist
                                                            : Icons.local_shipping,
                                                        size: 14,
                                                        color: Colors.white.withOpacity(0.7),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        userRole == 'driver'
                                                            ? '$count tasks'
                                                            : '$count loads',
                                                        style: TextStyle(
                                                            color: Colors.white.withOpacity(0.8),
                                                            fontSize: 12),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Icon(Icons.timer,
                                                          size: 14,
                                                          color: Colors.white.withOpacity(0.7)),
                                                      const SizedBox(width: 4),
                                                      Text(_formatDuration(seconds),
                                                          style: TextStyle(
                                                              color: Colors.white.withOpacity(0.8),
                                                              fontSize: 12)),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              );
                            }),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------- OWNER TEAM LIST SCREEN (all users) ----------------
class OwnerTeamListScreen extends StatelessWidget {
  const OwnerTeamListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text('Team',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final users = snapshot.data!.docs;
                    if (users.isEmpty) {
                      return const Center(
                        child: Text('No team members yet.', style: TextStyle(color: Colors.white)),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final doc = users[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final role = data['role'] ?? '';
                        final photoBase64 = data['photoBase64'] as String?;
                        Color roleColor = role == 'admin'
                            ? Colors.blue
                            : role == 'owner'
                                ? Colors.green
                                : role == 'driver'
                                    ? Colors.purple
                                    : Colors.orange;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: roleColor.withOpacity(0.15),
                                backgroundImage: photoBase64 != null
                                    ? MemoryImage(base64Decode(photoBase64))
                                    : null,
                                child: photoBase64 == null
                                    ? Icon(Icons.person, color: roleColor)
                                    : null,
                              ),
                              title: Text(data['name'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${data['email'] ?? ''}\nRole: $role'),
                              isThreeLine: true,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserProfileScreen(
                                      userId: doc.id,
                                      userName: data['name'] ?? '',
                                      userEmail: data['email'] ?? '',
                                      userRole: role,
                                      photoBase64: photoBase64,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------- TEAM CATEGORY SCREEN (Supervisors / Drivers) ----------------
class TeamCategoryScreen extends StatelessWidget {
  const TeamCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text('Team',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _WebStaggeredFadeIn(
                        index: 0,
                        child: DashboardMenuCard(
                          icon: Icons.engineering,
                          title: 'Supervisors',
                          subtitle: 'View supervisor profiles and history',
                          color: Colors.orange,
                          onTap: () {
                            pushWebAware(
                              context,
                              const RoleUserListScreen(
                                role: 'supervisor',
                                title: 'Supervisors',
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _WebStaggeredFadeIn(
                        index: 1,
                        child: DashboardMenuCard(
                          icon: Icons.local_shipping,
                          title: 'Drivers',
                          subtitle: 'View driver profiles and history',
                          color: Colors.purple,
                          onTap: () {
                            pushWebAware(
                              context,
                              const RoleUserListScreen(
                                role: 'driver',
                                title: 'Drivers',
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- ROLE-FILTERED USER LIST SCREEN ----------------
class RoleUserListScreen extends StatelessWidget {
  final String role;
  final String title;

  const RoleUserListScreen({super.key, required this.role, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('role', isEqualTo: role)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final users = snapshot.data!.docs;
                    if (users.isEmpty) {
                      return Center(
                        child: Text('No $title found.', style: const TextStyle(color: Colors.white)),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final doc = users[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final photoBase64 = data['photoBase64'] as String?;
                        final roleColor = role == 'driver' ? Colors.purple : Colors.orange;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _WebStaggeredFadeIn(
                            index: index,
                            child: _WebHoverCard(
                              child: Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: roleColor.withOpacity(0.15),
                                    backgroundImage: photoBase64 != null
                                        ? MemoryImage(base64Decode(photoBase64))
                                        : null,
                                    child: photoBase64 == null
                                        ? Icon(Icons.person, color: roleColor)
                                        : null,
                                  ),
                                  title: Text(data['name'] ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(data['email'] ?? ''),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    pushWebAware(
                                      context,
                                      UserProfileScreen(
                                        userId: doc.id,
                                        userName: data['name'] ?? '',
                                        userEmail: data['email'] ?? '',
                                        userRole: role,
                                        photoBase64: photoBase64,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------- TRUCK: SELECT TRUCK ----------------
class TruckTypeScreen extends StatelessWidget {
  final String name;
  const TruckTypeScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Select Truck',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('trucks').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final trucks = snapshot.data!.docs;
                    if (trucks.isEmpty) {
                      return const Center(
                        child: Text('No trucks registered yet. Contact Admin.',
                            style: TextStyle(color: Colors.white)),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: trucks.length,
                      itemBuilder: (context, index) {
                        final data = trucks[index].data() as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DashboardMenuCard(
                            icon: Icons.local_shipping,
                            title: data['truckNumber'] ?? '',
                            subtitle: 'Tap to select this truck',
                            color: Colors.deepOrange,
                            onTap: () async {
                              final today = DateTime.now();
                              final dateString =
                                  "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

                              final existing = await FirebaseFirestore.instance
                                  .collection('truck_sessions')
                                  .where('truckId', isEqualTo: trucks[index].id)
                                  .where('date', isEqualTo: dateString)
                                  .where('status', isEqualTo: 'active')
                                  .limit(1)
                                  .get();

                              String sessionId;
                              if (existing.docs.isNotEmpty) {
                                sessionId = existing.docs.first.id;
                              } else {
                                final docRef =
                                    await FirebaseFirestore.instance.collection('truck_sessions').add({
                                  'driverUid': FirebaseAuth.instance.currentUser!.uid,
                                  'driverName': name,
                                  'truckId': trucks[index].id,
                                  'truckNumber': data['truckNumber'] ?? '',
                                  'date': dateString,
                                  'status': 'active',
                                  'createdAt': FieldValue.serverTimestamp(),
                                });
                                sessionId = docRef.id;
                              }

                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TruckWorkAreaScreen(
                                      sessionId: sessionId,
                                      truckNumber: data['truckNumber'] ?? '',
                                      siteName: '',
                                      driverName: name,
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- TRUCK: SITE SELECT + CODE VERIFY ----------------
class TruckSiteSelectScreen extends StatefulWidget {
  final String name;
  final String truckId;
  final String truckNumber;

  const TruckSiteSelectScreen({
    super.key,
    required this.name,
    required this.truckId,
    required this.truckNumber,
  });

  @override
  State<TruckSiteSelectScreen> createState() => _TruckSiteSelectScreenState();
}

class _TruckSiteSelectScreenState extends State<TruckSiteSelectScreen> {
  String? _selectedSiteId;
  String? _selectedSiteName;
  final _codeController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submit() async {
    if (_selectedSiteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a site.')),
      );
      return;
    }
    if (_codeController.text.trim().length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 4-digit supervisor code.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final today = DateTime.now();
      final dateString =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      final supervisorMatch = await FirebaseFirestore.instance
          .collection('daily_sessions')
          .where('siteId', isEqualTo: _selectedSiteId)
          .where('date', isEqualTo: dateString)
          .where('status', isEqualTo: 'active')
          .where('verificationCode', isEqualTo: _codeController.text.trim())
          .limit(1)
          .get();

      if (supervisorMatch.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid code. Check with your supervisor.')),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      final existing = await FirebaseFirestore.instance
          .collection('truck_sessions')
          .where('truckId', isEqualTo: widget.truckId)
          .where('date', isEqualTo: dateString)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      String sessionId;

      if (existing.docs.isNotEmpty) {
        sessionId = existing.docs.first.id;
      } else {
        final docRef = await FirebaseFirestore.instance.collection('truck_sessions').add({
          'driverUid': FirebaseAuth.instance.currentUser!.uid,
          'driverName': widget.name,
          'truckId': widget.truckId,
          'truckNumber': widget.truckNumber,
          'siteId': _selectedSiteId,
          'siteName': _selectedSiteName,
          'supervisorSessionId': supervisorMatch.docs.first.id,
          'date': dateString,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        });
        sessionId = docRef.id;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TruckWorkAreaScreen(
              sessionId: sessionId,
              truckNumber: widget.truckNumber,
              siteName: _selectedSiteName ?? '',
              driverName: widget.name,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(widget.truckNumber,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Select Working Site',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 8),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('sites').snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const CircularProgressIndicator(color: Colors.white);
                            }
                            final sites = snapshot.data!.docs;
                            return DropdownButtonFormField<String>(
                              initialValue: _selectedSiteId,
                              dropdownColor: AppTheme.primaryMid,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Choose a site',
                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                                prefixIcon:
                                    Icon(Icons.location_on, color: Colors.white.withOpacity(0.7)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.accent),
                                ),
                              ),
                              items: sites.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return DropdownMenuItem<String>(
                                    value: doc.id, child: Text(data['name'] ?? ''));
                              }).toList(),
                              onChanged: (val) {
                                final selected = sites.firstWhere((d) => d.id == val);
                                final data = selected.data() as Map<String, dynamic>;
                                setState(() {
                                  _selectedSiteId = val;
                                  _selectedSiteName = data['name'];
                                });
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        const Text('Supervisor Code',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20, letterSpacing: 6),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '••••',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                            prefixIcon: Icon(Icons.vpn_key, color: Colors.white.withOpacity(0.7)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.accent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _isLoading
                            ? const Center(child: CircularProgressIndicator(color: Colors.white))
                            : GradientButton(
                                label: 'SUBMIT',
                                icon: Icons.check,
                                onTap: _submit,
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------- TRUCK: WORK AREA ----------------
class TruckWorkAreaScreen extends StatefulWidget {
  final String sessionId;
  final String truckNumber;
  final String siteName;
  final String driverName;

  const TruckWorkAreaScreen({
    super.key,
    required this.sessionId,
    required this.truckNumber,
    required this.siteName,
    required this.driverName,
  });

  @override
  State<TruckWorkAreaScreen> createState() => _TruckWorkAreaScreenState();
}

class _TruckWorkAreaScreenState extends State<TruckWorkAreaScreen> {
  @override
  void initState() {
    super.initState();
    TruckLocationService.startTracking(widget.sessionId, widget.truckNumber);
  }

  CollectionReference get _tripsRef => FirebaseFirestore.instance
      .collection('truck_sessions')
      .doc(widget.sessionId)
      .collection('trips');

  Future<bool> _hasOngoingTrip() async {
    final snap = await _tripsRef.where('status', isEqualTo: 'ongoing').limit(1).get();
    return snap.docs.isNotEmpty;
  }

  Future<void> _completeTrip(String tripId) async {
    await _tripsRef.doc(tripId).update({
      'status': 'completed',
      'endedAt': FieldValue.serverTimestamp(),
    });

    // Sync this completed trip to Google Sheets
    final updatedDoc = await _tripsRef.doc(tripId).get();
    final data = updatedDoc.data() as Map<String, dynamic>;

    final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
    final endedAt = (data['endedAt'] as Timestamp?)?.toDate();
    String durationText = '-';
    if (startedAt != null && endedAt != null) {
      final diff = endedAt.difference(startedAt);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      durationText = '${h}h ${m}m';
    }

    GoogleSheetsService.sendRow(
      sheetName: 'Truck_Trips',
      row: [
        GoogleSheetsService.formatDate(DateTime.now()),
        widget.truckNumber,
        widget.driverName,
        data['startSiteName'] ?? '',
        data['endSiteName'] ?? '',
        data['billNumber'] ?? '',
        GoogleSheetsService.formatTime(data['startedAt']),
        GoogleSheetsService.formatTime(data['endedAt']),
        durationText,
        data['cubeCount'] ?? '',
      ],
    );
  }

  void _showNewTripDialog() async {
    final ongoing = await _hasOngoingTrip();
    if (ongoing) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complete the current trip before starting a new one.')),
        );
      }
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => NewTripDialog(
        onSubmit: (startSiteName, endSiteId, endSiteName, billNumber, cubeCount) async {
          Navigator.pop(context);
          await _tripsRef.add({
            'startSiteName': startSiteName,
            'endSiteId': endSiteId,
            'endSiteName': endSiteName,
            'billNumber': billNumber,
            'cubeCount': cubeCount,
            'status': 'ongoing',
            'startedAt': FieldValue.serverTimestamp(),
            'endedAt': null,
          });
        },
      ),
    );
  }

  void _showEndDayDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Day'),
        content: const Text('Are you sure you want to end your work day?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final totalKm = await TruckLocationService.stopTrackingAndCalculateDistance();

              await FirebaseFirestore.instance
                  .collection('truck_sessions')
                  .doc(widget.sessionId)
                  .update({
                'status': 'completed',
                'completedAt': FieldValue.serverTimestamp(),
                'totalKm': totalKm,
              });

              // Columns: Date, Truck Number, Type, Location, Distance So Far (KM), Time
              GoogleSheetsService.sendRow(
                sheetName: 'Truck_Locations',
                row: [
                  GoogleSheetsService.formatDate(DateTime.now()),
                  widget.truckNumber,
                  'DAY SUMMARY',
                  'Total Distance',
                  '${totalKm.toStringAsFixed(2)} km',
                  GoogleSheetsService.formatTime(Timestamp.now()),
                ],
              );

              if (context.mounted) {
                Navigator.pop(context);
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            child: const Text('END DAY', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '-';
    final dt = ts.toDate();
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => TruckTypeScreen(name: widget.driverName),
                ),
              );
            }
          },
        ),
        title: Text(widget.truckNumber),
        backgroundColor: Colors.deepOrange[800],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.deepOrange[50],
            child: Text(
              'Truck: ${widget.truckNumber}  •  Driver: ${widget.driverName}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _tripsRef.orderBy('startedAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final trips = snapshot.data!.docs;
                if (trips.isEmpty) {
                  return const Center(
                      child: Text('No trips yet.\nTap "+ NEW TASK" to begin.',
                          textAlign: TextAlign.center));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: trips.length,
                  itemBuilder: (context, index) {
                    final doc = trips[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isOngoing = data['status'] == 'ongoing';

                    return Card(
                      color: isOngoing ? Colors.green[50] : Colors.white,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isOngoing ? Colors.green : Colors.grey[300]!,
                          width: isOngoing ? 1.5 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${data['startSiteName']} → ${data['endSiteName']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ),
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isOngoing ? Colors.green : Colors.grey[400],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isOngoing ? 'ONGOING' : 'DONE',
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TripTimerText(
                              isOngoing: isOngoing,
                              startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
                              endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
                            ),
                            if (data['billNumber'] != null &&
                                data['billNumber'].toString().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('Bill Number: ${data['billNumber']}',
                                  style: const TextStyle(fontSize: 13)),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              'Started: ${_formatTime(data['startedAt'] as Timestamp?)}'
                              '${data['endedAt'] != null ? "  •  Ended: ${_formatTime(data['endedAt'] as Timestamp?)}" : ""}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            if (isOngoing) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _completeTrip(doc.id),
                                  icon: const Icon(Icons.check, color: Colors.white),
                                  label: const Text('COMPLETE TASK',
                                      style: TextStyle(color: Colors.white)),
                                  style:
                                      ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewTripDialog,
        backgroundColor: Colors.deepOrange[800],
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('NEW TASK', style: TextStyle(color: Colors.white)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _showEndDayDialog,
              icon: const Icon(Icons.flag, color: Colors.white),
              label: const Text('END DAY',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- NEW TRIP DIALOG (Truck) ----------------
class NewTripDialog extends StatefulWidget {
  final Function(String? startSiteName, String? endSiteId, String? endSiteName,
      String? billNumber, String? cubeCount) onSubmit;

  const NewTripDialog({super.key, required this.onSubmit});

  @override
  State<NewTripDialog> createState() => _NewTripDialogState();
}

class _NewTripDialogState extends State<NewTripDialog> {
  String? _selectedStartSiteId;
  String? _selectedStartSiteName;
  String? _selectedEndSiteId;
  String? _selectedEndSiteName;
  final _billNumberController = TextEditingController();
  final _cubeController = TextEditingController();
  String _errorText = '';

  void _handleSubmit() {
    if (_selectedStartSiteId == null) {
      setState(() => _errorText = 'Please select the start site.');
      return;
    }
    if (_selectedEndSiteId == null) {
      setState(() => _errorText = 'Please select the end site.');
      return;
    }
    widget.onSubmit(
      _selectedStartSiteName,
      _selectedEndSiteId,
      _selectedEndSiteName,
      _billNumberController.text.trim().isEmpty ? null : _billNumberController.text.trim(),
      _cubeController.text.trim().isEmpty ? null : _cubeController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Start New Task'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Start Site', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('sites').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final sites = snapshot.data!.docs;
                return DropdownButtonFormField<String>(
                  initialValue: _selectedStartSiteId,
                  decoration: InputDecoration(
                    hintText: 'Choose start site',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: sites.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return DropdownMenuItem<String>(value: doc.id, child: Text(data['name'] ?? ''));
                  }).toList(),
                  onChanged: (val) {
                    final selected = sites.firstWhere((d) => d.id == val);
                    final data = selected.data() as Map<String, dynamic>;
                    setState(() {
                      _selectedStartSiteId = val;
                      _selectedStartSiteName = data['name'];
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            const Text('End Site', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('sites').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final sites = snapshot.data!.docs;
                return DropdownButtonFormField<String>(
                  initialValue: _selectedEndSiteId,
                  decoration: InputDecoration(
                    hintText: 'Choose end site',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: sites.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return DropdownMenuItem<String>(value: doc.id, child: Text(data['name'] ?? ''));
                  }).toList(),
                  onChanged: (val) {
                    final selected = sites.firstWhere((d) => d.id == val);
                    final data = selected.data() as Map<String, dynamic>;
                    setState(() {
                      _selectedEndSiteId = val;
                      _selectedEndSiteName = data['name'];
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _billNumberController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Bill Number (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cubeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Cube (Quantity)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            if (_errorText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_errorText, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _handleSubmit,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange[800]),
          child: const Text('START', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
// ---------------- TRUCK MANAGEMENT SCREEN (Admin) ----------------
class TruckManagementScreen extends StatefulWidget {
  const TruckManagementScreen({super.key});

  @override
  State<TruckManagementScreen> createState() => _TruckManagementScreenState();
}

class _TruckManagementScreenState extends State<TruckManagementScreen> {
  final _truckNumberController = TextEditingController();
  String? _selectedDriverUid;
  String? _selectedDriverName;

  Future<void> _addTruck() async {
    final enteredTruckNumber = _truckNumberController.text.trim();
    if (enteredTruckNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a truck number.')),
      );
      return;
    }

    final existingTrucks = await FirebaseFirestore.instance.collection('trucks').get();
    final normalizedEntry = enteredTruckNumber.trim().toUpperCase();
    final isDuplicate = existingTrucks.docs.any((doc) {
      final data = doc.data();
      final existingNumber = (data['truckNumber'] as String?)?.trim().toUpperCase() ?? '';
      return existingNumber == normalizedEntry;
    });

    if (isDuplicate) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This truck number is already registered.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await FirebaseFirestore.instance.collection('trucks').add({
      'truckNumber': enteredTruckNumber,
      'assignedDriverUid': _selectedDriverUid,
      'assignedDriverName': _selectedDriverName,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _truckNumberController.clear();
    setState(() {
      _selectedDriverUid = null;
      _selectedDriverName = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Truck added successfully!')),
      );
    }
  }

  Future<void> _deleteTruck(String docId) async {
    await FirebaseFirestore.instance.collection('trucks').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Trucks'),
        backgroundColor: Colors.deepOrange[800],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _truckNumberController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Truck Number / Plate',
                    prefixIcon: const Icon(Icons.local_shipping),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('canDriveTruck', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    final drivers = snapshot.data!.docs;
                    return DropdownButtonFormField<String>(
                      initialValue: _selectedDriverUid,
                      decoration: InputDecoration(
                        labelText: 'Assign Driver (optional)',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: drivers.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(data['name'] ?? ''),
                        );
                      }).toList(),
                      onChanged: (val) {
                        final selected = drivers.firstWhere((d) => d.id == val);
                        final data = selected.data() as Map<String, dynamic>;
                        setState(() {
                          _selectedDriverUid = val;
                          _selectedDriverName = data['name'];
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _addTruck,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('ADD TRUCK', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('trucks')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No trucks added yet.'));
                }

                final trucks = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: trucks.length,
                  itemBuilder: (context, index) {
                    final data = trucks[index].data() as Map<String, dynamic>;
                    final docId = trucks[index].id;

                    return _WebStaggeredFadeIn(
                      index: index,
                      child: _WebHoverCard(
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.deepOrange.withOpacity(0.15),
                              child: const Icon(Icons.local_shipping, color: Colors.deepOrange),
                            ),
                            title: Text(data['truckNumber'] ?? ''),
                            subtitle: Text(data['assignedDriverName'] != null
                                ? 'Driver: ${data['assignedDriverName']}'
                                : 'No driver assigned'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteTruck(docId),
                            ),
                            onTap: () {
                              pushWebAware(
                                context,
                                TruckProfileScreen(
                                  truckId: docId,
                                  truckNumber: data['truckNumber'] ?? '',
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
// ---------------- TRUCK PROFILE SCREEN (Admin/Owner) ----------------
class TruckProfileScreen extends StatelessWidget {
  final String truckId;
  final String truckNumber;

  const TruckProfileScreen({super.key, required this.truckId, required this.truckNumber});

  void _showChangeDriverDialog(BuildContext context, String? currentDriverUid) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Change Assigned Driver'),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('canDriveTruck', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final drivers = snapshot.data!.docs;
              if (drivers.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No drivers available.'),
                );
              }
              return SizedBox(
                height: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: drivers.length,
                  itemBuilder: (context, index) {
                    final data = drivers[index].data() as Map<String, dynamic>;
                    final uid = drivers[index].id;
                    final isSelected = uid == currentDriverUid;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.deepOrange.withOpacity(0.15),
                        child: const Icon(Icons.person, color: Colors.deepOrange),
                      ),
                      title: Text(data['name'] ?? ''),
                      trailing: isSelected ? const Icon(Icons.check, color: Colors.deepOrange) : null,
                      onTap: () async {
                        await FirebaseFirestore.instance.collection('trucks').doc(truckId).update({
                          'assignedDriverUid': uid,
                          'assignedDriverName': data['name'] ?? '',
                        });
                        if (context.mounted) Navigator.pop(context);
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '-';
    final dt = ts.toDate();
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  String _formatDateHeader(String dateString) {
    final parts = dateString.split('-');
    if (parts.length != 3) return dateString;
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final today = DateTime.now();
    final todayStr =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    if (dateString == todayStr) return 'Today';
    final yesterday = today.subtract(const Duration(days: 1));
    final yestStr =
        "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";
    if (dateString == yestStr) return 'Yesterday';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  static const List<Color> _dayColors = [
    Color(0xFF3D9DE0), Color(0xFF4CAF7D), Color(0xFFE0A93D), Color(0xFF9B6BE0),
    Color(0xFFE05C97), Color(0xFF3DBFC4), Color(0xFFEF6C57), Color(0xFF7D8CE0),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(truckNumber,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('truck_sessions')
                      .where('truckId', isEqualTo: truckId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final sessions = snapshot.data!.docs;

                    // Find current active session for "where is it now" summary
                    QueryDocumentSnapshot? activeSession;
                    for (final doc in sessions) {
                      final data = doc.data() as Map<String, dynamic>;
                      if (data['status'] == 'active') {
                        activeSession = doc;
                        break;
                      }
                    }

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('trucks')
                                .doc(truckId)
                                .snapshots(),
                            builder: (context, truckSnap) {
                              final truckData = truckSnap.data?.data() as Map<String, dynamic>?;
                              final assignedDriverName = truckData?['assignedDriverName'];
                              final assignedDriverUid = truckData?['assignedDriverUid'];

                              return GlassCard(
                                child: Column(
                                  children: [
                                    Icon(
                                      activeSession != null
                                          ? Icons.play_circle_fill
                                          : Icons.pause_circle,
                                      color: activeSession != null ? Colors.green : Colors.grey,
                                      size: 36,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      activeSession != null ? 'Currently Active' : 'Not Working Now',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                    if (activeSession != null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Site: ${(activeSession.data() as Map)['siteName'] ?? '-'}',
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                      ),
                                    ],
                                    const Divider(color: Colors.white24, height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Assigned Driver',
                                                style: TextStyle(
                                                    color: Colors.white.withOpacity(0.6), fontSize: 11)),
                                            Text(assignedDriverName ?? 'Not assigned',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14)),
                                          ],
                                        ),
                                        TextButton.icon(
                                          onPressed: () =>
                                              _showChangeDriverDialog(context, assignedDriverUid),
                                          icon: const Icon(Icons.edit, size: 16, color: AppTheme.accent),
                                          label: const Text('Change',
                                              style: TextStyle(color: AppTheme.accent)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          const Text('History',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 12),
                          if (sessions.isEmpty)
                            const Text('No history yet.', style: TextStyle(color: Colors.white))
                          else
                            Builder(builder: (context) {
                              final Map<String, List<QueryDocumentSnapshot>> grouped = {};
                              for (final doc in sessions) {
                                final data = doc.data() as Map<String, dynamic>;
                                final date = data['date'] ?? 'unknown';
                                grouped.putIfAbsent(date, () => []).add(doc);
                              }
                              final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

                              return Column(
                                children: List.generate(sortedDates.length, (dateIndex) {
                                  final date = sortedDates[dateIndex];
                                  final dayColor = _dayColors[dateIndex % _dayColors.length];
                                  final daySessions = grouped[date]!;

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 10, height: 10,
                                              decoration: BoxDecoration(
                                                  color: dayColor, shape: BoxShape.circle),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(_formatDateHeader(date),
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15)),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        ...daySessions.map((doc) {
                                          final data = doc.data() as Map<String, dynamic>;
                                          final isActive = data['status'] == 'active';

                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 10, left: 18),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border(
                                                    left: BorderSide(color: dayColor, width: 4)),
                                              ),
                                              padding: const EdgeInsets.all(14),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          '${data['siteName'] ?? ''} • ${data['driverName'] ?? ''}',
                                                          style: const TextStyle(
                                                              color: Colors.white,
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 14),
                                                        ),
                                                      ),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: isActive
                                                              ? Colors.green
                                                              : Colors.grey,
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: Text(
                                                          isActive ? 'ACTIVE' : 'DONE',
                                                          style: const TextStyle(
                                                              color: Colors.white, fontSize: 10),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Started: ${_formatTime(data['createdAt'] as Timestamp?)}'
                                                    '${data['completedAt'] != null ? "  •  Ended: ${_formatTime(data['completedAt'] as Timestamp?)}" : ""}',
                                                    style: TextStyle(
                                                        color: Colors.white.withOpacity(0.6),
                                                        fontSize: 11),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  StreamBuilder<QuerySnapshot>(
                                                    stream: FirebaseFirestore.instance
                                                        .collection('truck_sessions')
                                                        .doc(doc.id)
                                                        .collection('trips')
                                                        .snapshots(),
                                                    builder: (context, tripSnap) {
                                                      if (!tripSnap.hasData) {
                                                        return const SizedBox.shrink();
                                                      }
                                                      final tripCount = tripSnap.data!.docs.length;
                                                      return Row(
                                                        children: [
                                                          Icon(Icons.route,
                                                              size: 14,
                                                              color: Colors.white.withOpacity(0.7)),
                                                          const SizedBox(width: 4),
                                                          Text('$tripCount trip(s)',
                                                              style: TextStyle(
                                                                  color:
                                                                      Colors.white.withOpacity(0.8),
                                                                  fontSize: 12)),
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                }),
                              );
                            }),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- MACHINE PROFILE SCREEN (Admin/Owner) ----------------
class MachineProfileScreen extends StatelessWidget {
  final String machineId;
  final String machineName;
  final String machineType;
  final String machineNumber;

  const MachineProfileScreen({
    super.key,
    required this.machineId,
    required this.machineName,
    required this.machineType,
    required this.machineNumber,
  });

  @override
  Widget build(BuildContext context) {
    // Machines are used by both Supervisors (daily_sessions) and
    // Operators (driver_sessions) - show both histories combined.
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mainGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text('$machineName ($machineNumber)',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlassCard(
                        child: Column(
                          children: [
                            const Icon(Icons.precision_manufacturing,
                                color: Colors.white, size: 36),
                            const SizedBox(height: 8),
                            Text(machineName,
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('$machineType • $machineNumber',
                                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Supervisor Sessions',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 10),
                      _MachineSessionList(
                        collectionName: 'daily_sessions',
                        machineId: machineId,
                      ),
                      const SizedBox(height: 20),
                      const Text('Operator Sessions',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 10),
                      _MachineSessionList(
                        collectionName: 'driver_sessions',
                        machineId: machineId,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MachineSessionList extends StatelessWidget {
  final String collectionName;
  final String machineId;

  const _MachineSessionList({required this.collectionName, required this.machineId});

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '-';
    final dt = ts.toDate();
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(collectionName)
          .where('machineId', isEqualTo: machineId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        final sessions = snapshot.data!.docs
          ..sort((a, b) {
            final aDate = (a.data() as Map)['date'] ?? '';
            final bDate = (b.data() as Map)['date'] ?? '';
            return bDate.compareTo(aDate);
          });

        if (sessions.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('No sessions yet.', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          );
        }

        return Column(
          children: sessions.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isActive = data['status'] == 'active';
            final personName = data['supervisorName'] ?? data['driverName'] ?? '-';

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('${data['date']} • ${data['siteName'] ?? ''}',
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.green : Colors.grey,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(isActive ? 'ACTIVE' : 'DONE',
                              style: const TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('By: $personName',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                    Text(
                      'Started: ${_formatTime(data['createdAt'] as Timestamp?)}'
                      '${data['completedAt'] != null ? "  •  Ended: ${_formatTime(data['completedAt'] as Timestamp?)}" : ""}',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
// ---------------- TRIP TIMER TEXT (live duration for truck trips) ----------------
class TripTimerText extends StatefulWidget {
  final bool isOngoing;
  final DateTime? startedAt;
  final DateTime? endedAt;

  const TripTimerText({
    super.key,
    required this.isOngoing,
    required this.startedAt,
    this.endedAt,
  });

  @override
  State<TripTimerText> createState() => _TripTimerTextState();
}

class _TripTimerTextState extends State<TripTimerText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.isOngoing) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.startedAt == null) return const SizedBox.shrink();

    final endTime = widget.endedAt ?? DateTime.now();
    final duration = endTime.difference(widget.startedAt!);

    return Row(
      children: [
        Icon(Icons.timer, size: 16, color: widget.isOngoing ? Colors.green[700] : Colors.grey[600]),
        const SizedBox(width: 6),
        Text(
          _formatDuration(duration),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: widget.isOngoing ? Colors.green[700] : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
// ---------------- TRUCK LOCATION TRACKING SERVICE ----------------
class TruckLocationService {
  static StreamSubscription<Position>? _positionStream;
  static String? _activeSessionId;
  static String? _activeTruckNumber;
  static Position? _lastRecordedPosition;
  static double _cumulativeDistanceKm = 0.0;

  static Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    // Request background permission too (Android 10+)
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }

    return true;
  }

  static Future<void> startTracking(String sessionId, String truckNumber) async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    _activeSessionId = sessionId;
    _activeTruckNumber = truckNumber;
    _lastRecordedPosition = null;
    _cumulativeDistanceKm = 0.0;

    // Record the starting point immediately
    try {
      final startPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _recordPoint(startPos, isStart: true);
      _lastRecordedPosition = startPos;
    } catch (e) {
      // ignore initial failure, stream will catch up
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 300, // meters - only record when moved 300m+
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position position) async {
        if (_isDuplicateOfLastRecorded(position)) return;
        await _recordPoint(position, isStart: false);
        _lastRecordedPosition = position;
      },
    );
  }

  // Rounds to 5 decimal places (~1.1m precision) so GPS jitter doesn't
  // register as movement while emulator/repeat fixes at the same spot do
  // register as duplicates.
  static double _roundCoord(double value) => (value * 100000).round() / 100000;

  static bool _isDuplicateOfLastRecorded(Position position) {
    final last = _lastRecordedPosition;
    if (last == null) return false;
    return _roundCoord(position.latitude) == _roundCoord(last.latitude) &&
        _roundCoord(position.longitude) == _roundCoord(last.longitude);
  }

  static Future<void> _recordPoint(Position position, {required bool isStart}) async {
    if (_activeSessionId == null) return;

    // Accumulate distance from the previously recorded point (still held in
    // _lastRecordedPosition at this point - the caller updates it after this
    // method returns). isStart points have no previous point yet, so this is
    // a no-op and the running total correctly starts at 0.
    final previous = _lastRecordedPosition;
    if (previous != null) {
      _cumulativeDistanceKm += Geolocator.distanceBetween(
            previous.latitude,
            previous.longitude,
            position.latitude,
            position.longitude,
          ) /
          1000.0;
    }

    await FirebaseFirestore.instance
        .collection('truck_sessions')
        .doc(_activeSessionId)
        .collection('location_points')
        .add({
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': FieldValue.serverTimestamp(),
      'isStart': isStart,
    });

    // Update the "latest location" field on the session for live tracking
    await FirebaseFirestore.instance.collection('truck_sessions').doc(_activeSessionId).update({
      'lastLat': position.latitude,
      'lastLng': position.longitude,
      'lastLocationAt': FieldValue.serverTimestamp(),
    });

    // Sync this stop to Google Sheets in real time (reverse geocoded)
    try {
      List<Placemark> placemarks =
          await Geocoding().placemarkFromCoordinates(position.latitude, position.longitude);
      String placeName = 'Unknown location';
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        placeName = [p.locality, p.subAdministrativeArea, p.administrativeArea]
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        if (placeName.isEmpty) placeName = 'Unknown location';
      }

      // Columns: Date, Truck Number, Type, Location, Distance So Far (KM), Time
      GoogleSheetsService.sendRow(
        sheetName: 'Truck_Locations',
        row: [
          GoogleSheetsService.formatDate(DateTime.now()),
          _activeTruckNumber ?? '',
          isStart ? 'START' : 'STOP',
          placeName,
          '${_cumulativeDistanceKm.toStringAsFixed(2)} km',
          GoogleSheetsService.formatTime(Timestamp.now()),
        ],
      );
    } catch (e) {
      // Reverse geocoding can fail silently without breaking tracking
    }
  }

  static Future<double> stopTrackingAndCalculateDistance() async {
    await _positionStream?.cancel();
    _positionStream = null;

    if (_activeSessionId == null) return 0.0;

    final pointsSnap = await FirebaseFirestore.instance
        .collection('truck_sessions')
        .doc(_activeSessionId)
        .collection('location_points')
        .orderBy('timestamp')
        .get();

    double totalKm = 0.0;
    GeoPoint? previous;

    for (final doc in pointsSnap.docs) {
      final data = doc.data();
      final lat = data['lat'] as double;
      final lng = data['lng'] as double;

      if (previous != null) {
        totalKm += Geolocator.distanceBetween(
              previous.latitude,
              previous.longitude,
              lat,
              lng,
            ) /
            1000.0;
      }
      previous = GeoPoint(lat, lng);
    }

    _activeSessionId = null;
    _activeTruckNumber = null;
    _lastRecordedPosition = null;
    _cumulativeDistanceKm = 0.0;

    return totalKm;
  }
}
// ---------------- LOGIN FORM CARD (opaque white, for readable form fields) ----------------
class LoginFormCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const LoginFormCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
