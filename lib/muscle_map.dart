// muscle_map.dart
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart' show WebViewController;

import 'glass_ui.dart'; // uses your shared GlassCard + ActionButton
import 'package_config_page.dart'; // <-- if you named it package_config_page.dart, change this import

/// ---------- CARD: shows in Home, opens the page ----------
class MuscleMapCard extends StatelessWidget {
  final String fireBaseId; // NEW: needed to open Package Config
  const MuscleMapCard({super.key, required this.fireBaseId});

  void _openMuscleMap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MuscleMapPage()),
    );
  }

  void _openPackageConfig(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PackageConfigPage(fireBaseId: fireBaseId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double anchorIconSize = 36;
    const double anchorRightPadding = 142;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;

            final anchor = Offset(
              w - anchorRightPadding - anchorIconSize / 2,
              h / 2,
            );

            // Keep pinned label & anchor as in your original.
            // Replace the big heading/subheading/button area with two compact actions side-by-side.
            final content = Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 120.0),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ActionButton(
                            icon: Icons.self_improvement,
                            label: 'Open Muscle Map',
                            bg: Colors.white, // white chip -> black icon
                            circleSize: 36,
                            iconSize: 18,
                            labelGap: 8,
                            onTap: () => _openMuscleMap(context),
                          ),
                          ActionButton(
                            icon: Icons.inventory_2_outlined,
                            label: 'Configure Packages',
                            bg: const Color(0xFFFFCA28), // amber chip
                            circleSize: 36,
                            iconSize: 18,
                            labelGap: 8,
                            onTap: () => _openPackageConfig(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );

            final pinnedLabel = const Positioned(
              left: 12,
              top: 12,
              child: Row(
                children: [
                  Icon(
                    Icons.self_improvement,
                    color: Color(0xFF4F9CF9),
                    size: 16,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Muscle Map',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            );

            final anchorWidget = Positioned(
              left: anchor.dx - anchorIconSize / 2,
              top: anchor.dy - anchorIconSize / 2,
              child: Container(
                width: anchorIconSize,
                height: anchorIconSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2A2F3A),
                ),
                child: const Icon(
                  Icons.self_improvement,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            );

            return Stack(
              clipBehavior: Clip.none,
              children: [content, pinnedLabel, anchorWidget],
            );
          },
        ),
      ),
    );
  }
}

/// ---------- PAGE: interactive 3D model with hotspots ----------
class MuscleMapPage extends StatefulWidget {
  const MuscleMapPage({super.key});

  @override
  State<MuscleMapPage> createState() => _MuscleMapPageState();
}

class _MuscleMapPageState extends State<MuscleMapPage> {
  WebViewController?
  _mvController; // model_viewer_plus -> WebView under the hood

  // Camera defaults
  static const String _orbitFront = '0deg 75deg 2m';
  static const String _orbitBack = '180deg 75deg 2m';
  static const String _defaultTarget = '0m 1m 0m';

  // FRONT/BACK toggle state: 0=Front, 1=Both, 2=Back
  int _sideIndex = 1;

  // Minimal dataset
  final List<_Muscle> _muscles = const [
    _Muscle(
      id: 'pectoralis_major',
      name: 'Pectoralis Major',
      group: 'Chest',
      position: '0m 1.25m 0.08m',
      normal: '0 0 1',
    ),
    _Muscle(
      id: 'deltoid',
      name: 'Deltoid',
      group: 'Shoulders',
      position: '0.22m 1.40m 0.05m',
      normal: '0 0 1',
    ),
    _Muscle(
      id: 'biceps_brachii',
      name: 'Biceps Brachii',
      group: 'Arms',
      position: '0.25m 1.15m 0.10m',
      normal: '0 0 1',
    ),
    _Muscle(
      id: 'rectus_abdominis',
      name: 'Rectus Abdominis',
      group: 'Core',
      position: '0m 1.05m 0.10m',
      normal: '0 0 1',
    ),
    _Muscle(
      id: 'quadriceps',
      name: 'Quadriceps Femoris',
      group: 'Legs',
      position: '0m 0.65m 0.12m',
      normal: '0 0 1',
    ),
    _Muscle(
      id: 'gastrocnemius',
      name: 'Gastrocnemius',
      group: 'Legs',
      position: '0m 0.30m 0.10m',
      normal: '0 0 1',
    ),
    _Muscle(
      id: 'trapezius',
      name: 'Trapezius',
      group: 'Back',
      position: '0m 1.45m -0.08m',
      normal: '0 0 -1',
    ),
    _Muscle(
      id: 'latissimus_dorsi',
      name: 'Latissimus Dorsi',
      group: 'Back',
      position: '0.10m 1.10m -0.14m',
      normal: '0 0 -1',
    ),
    _Muscle(
      id: 'gluteus_maximus',
      name: 'Gluteus Maximus',
      group: 'Glutes',
      position: '0m 0.85m -0.12m',
      normal: '0 0 -1',
    ),
    _Muscle(
      id: 'hamstrings',
      name: 'Hamstrings',
      group: 'Legs',
      position: '0m 0.60m -0.12m',
      normal: '0 0 -1',
    ),
  ];

  late final Set<String> _groups = _muscles.map((m) => m.group).toSet();
  final Set<String> _activeGroups = {};

  String get _innerHotspotsHtml {
    final buf = StringBuffer();
    for (final m in _muscles) {
      final hidden =
          _activeGroups.isNotEmpty && !_activeGroups.contains(m.group);
      buf.writeln(
        '<button class="hotspot" '
        'slot="hotspot-${m.id}" '
        'data-id="${m.id}" '
        'data-name="${m.name}" '
        'data-group="${m.group}" '
        'data-position="${m.position}" '
        'data-normal="${m.normal}" '
        'data-visibility-attribute="visible" '
        'style="${hidden ? 'display:none' : ''}">'
        '${m.name}'
        '</button>',
      );
    }
    return buf.toString();
  }

  final Map<String, String> _shortFacts = const {
    'pectoralis_major': 'Chest push/press, fly, dips',
    'deltoid': 'Overhead press, lateral raise',
    'biceps_brachii': 'Curls (barbell/dumbbell), chin-ups',
    'rectus_abdominis': 'Crunch, plank, leg raise',
    'quadriceps': 'Squat, leg press, lunge',
    'gastrocnemius': 'Standing/seated calf raises',
    'trapezius': 'Shrugs, face pulls, rows',
    'latissimus_dorsi': 'Pull-ups, lat pulldown, rows',
    'gluteus_maximus': 'Hip thrust, deadlift, squat',
    'hamstrings': 'RDL, leg curl, hip hinge',
  };

  final Map<String, List<String>> _exerciseLibrary = const {
    'pectoralis_major': [
      'Barbell Bench Press',
      'Incline Dumbbell Press',
      'Cable Fly',
      'Dips',
    ],
    'deltoid': [
      'Overhead Press',
      'Lateral Raise',
      'Front Raise',
      'Reverse Pec Deck',
    ],
    'biceps_brachii': [
      'Barbell Curl',
      'Dumbbell Curl',
      'Preacher Curl',
      'Chin-Up',
    ],
    'rectus_abdominis': [
      'Crunch',
      'Hanging Leg Raise',
      'Plank',
      'Cable Crunch',
    ],
    'quadriceps': ['Back Squat', 'Front Squat', 'Leg Press', 'Walking Lunge'],
    'gastrocnemius': [
      'Standing Calf Raise',
      'Seated Calf Raise',
      'Donkey Calf Raise',
    ],
    'trapezius': [
      'Barbell Shrug',
      'Dumbbell Shrug',
      'Face Pull',
      'Upright Row (careful)',
    ],
    'latissimus_dorsi': [
      'Pull-Up',
      'Lat Pulldown',
      'One-Arm Dumbbell Row',
      'Seated Cable Row',
    ],
    'gluteus_maximus': [
      'Hip Thrust',
      'Romanian Deadlift',
      'Back Squat',
      'Glute Bridge',
    ],
    'hamstrings': [
      'Romanian Deadlift',
      'Lying Leg Curl',
      'Good Morning',
      'Nordic Curl',
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Muscle Map'),
        actions: [
          IconButton(
            tooltip: 'Search muscle',
            icon: const Icon(Icons.search),
            onPressed: _openMusclePicker,
          ),
          IconButton(
            tooltip: 'Reset view',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: _resetCamera,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTopControls(),
          const Divider(height: 1),
          Expanded(
            child: ModelViewer(
              id: 'muscle-mv',
              src: 'assets/models/human_muscles.glb',
              alt: 'Human muscular system',
              backgroundColor: Colors.black,
              cameraControls: true,
              autoRotate: true,
              minFieldOfView: '15deg',
              maxFieldOfView: '65deg',
              cameraOrbit: _orbitFront,
              cameraTarget: _defaultTarget,
              innerModelViewerHtml: _innerHotspotsHtml,
              relatedCss: _relatedCss,
              relatedJs: _relatedJs,
              // ❌ No javascriptChannels here to avoid type/version conflicts.
              onWebViewCreated: (WebViewController controller) {
                _mvController = controller;
                // ✅ Register the JS channel directly on the controller.
                _mvController?.addJavaScriptChannel(
                  'Hotspot',
                  onMessageReceived: (message) {
                    _showMuscleSheet(message.message);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ToggleButtons(
            isSelected: [_sideIndex == 0, _sideIndex == 1, _sideIndex == 2],
            borderRadius: BorderRadius.circular(10),
            constraints: const BoxConstraints(minHeight: 36, minWidth: 64),
            onPressed: (idx) {
              setState(() => _sideIndex = idx);
              _applySideFilterToWebView();
              _jumpToSideCamera();
            },
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Front'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Both'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Back'),
              ),
            ],
          ),
          const SizedBox(width: 12),
          const VerticalDivider(width: 1),
          const SizedBox(width: 12),
          ..._groups.map((g) {
            final selected = _activeGroups.contains(g);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(g),
                selected: selected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _activeGroups.add(g);
                    } else {
                      _activeGroups.remove(g);
                    }
                  });
                  _applyGroupFilterToWebView();
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  void _applyGroupFilterToWebView() {
    if (_mvController == null) return;
    final groupsJs =
        '[${_activeGroups.map((g) => '\'${g.replaceAll("'", "\\'")}\'').join(',')}]';
    final script =
        '''
      (function(){
        const allowed = new Set($groupsJs);
        document.querySelectorAll('button.hotspot').forEach(btn => {
          const g = btn.getAttribute('data-group');
          if(allowed.size === 0 || allowed.has(g)) btn.style.display='';
          else btn.style.display='none';
        });
      })();
    ''';
    _mvController!.runJavaScript(script);
  }

  void _applySideFilterToWebView() {
    if (_mvController == null) return;
    final side = (_sideIndex == 0)
        ? 'front'
        : (_sideIndex == 2)
        ? 'back'
        : 'both';
    final script =
        '''
      (function(){
        const side = '$side';
        document.querySelectorAll('button.hotspot').forEach(btn => {
          const normal = (btn.getAttribute('data-normal')||'0 0 1').trim();
          const nz = parseFloat(normal.split(/\\s+/).pop());
          const isFront = nz >= 0; // +Z => front
          if (side === 'both') {
            btn.style.visibility = '';
          } else if (side === 'front') {
            btn.style.visibility = isFront ? '' : 'hidden';
          } else {
            btn.style.visibility = isFront ? 'hidden' : '';
          }
        });
      })();
    ''';
    _mvController!.runJavaScript(script);
  }

  void _jumpToSideCamera() {
    if (_mvController == null) return;
    final orbit = (_sideIndex == 2) ? _orbitBack : _orbitFront;
    _mvController!.runJavaScript('''
      (function(){
        const mv = document.querySelector('model-viewer');
        mv.cameraOrbit = '$orbit';
        mv.cameraTarget = '$_defaultTarget';
        mv.jumpCameraToGoal();
      })();
    ''');
  }

  void _openMusclePicker() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text(
                    'Jump to muscle',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: _muscles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final m = _muscles[i];
                      return ListTile(
                        title: Text(m.name),
                        subtitle: Text(m.group),
                        onTap: () => Navigator.of(ctx).pop(m.id),
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
    if (choice != null) {
      _focusMuscle(choice);
    }
  }

  void _resetCamera() {
    if (_mvController == null) return;
    final orbit = (_sideIndex == 2) ? _orbitBack : _orbitFront;
    _mvController!.runJavaScript('''
      (function(){
        const mv = document.querySelector('model-viewer');
        mv.cameraOrbit = '$orbit';
        mv.cameraTarget = '$_defaultTarget';
        mv.jumpCameraToGoal();
      })();
    ''');
  }

  void _focusMuscle(String id) {
    if (_mvController == null) return;
    final safeId = id.replaceAll("'", "\\'");
    _mvController!.runJavaScript("window.focusHotspot('$safeId')");
  }

  void _showMuscleSheet(String id) {
    final m = _muscles.firstWhere(
      (x) => x.id == id,
      orElse: () => _muscles.first,
    );
    final tips = _shortFacts[id];
    final exercises = _exerciseLibrary[id] ?? const <String>[];
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  m.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  m.group,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.primary),
                ),
                const SizedBox(height: 12),
                if (tips != null) ...[
                  const Text(
                    'Training ideas',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(tips),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _focusMuscle(id);
                      },
                      icon: const Icon(Icons.center_focus_strong),
                      label: const Text('Focus'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ExerciseListPage(
                              muscleId: id,
                              muscleName: m.name,
                              exercises: exercises,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.fitness_center),
                      label: const Text('View exercises'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Muscle {
  final String id;
  final String name;
  final String group;
  final String position; // e.g., '0m 1.2m 0.1m'
  final String normal; // e.g., '0 0 1'
  const _Muscle({
    required this.id,
    required this.name,
    required this.group,
    required this.position,
    required this.normal,
  });
}

// ----- CSS injected into the WebView -----
const String _relatedCss = '''
  :root { --hotspot-bg: rgba(255,255,255,0.92); --hotspot-txt: #111; }
  button.hotspot {
    position: relative;
    transform: translate(-50%, -50%);
    font: 500 12px system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, 'Helvetica Neue', Arial, sans-serif;
    color: var(--hotspot-txt);
    background: var(--hotspot-bg);
    padding: 4px 8px;
    border: 0;
    border-radius: 10px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.25);
    white-space: nowrap;
    cursor: pointer;
  }
  button.hotspot::after {
    content: '';
    position: absolute;
    left: 50%;
    top: 100%;
    width: 2px; height: 14px;
    background: var(--hotspot-bg);
    transform: translateX(-50%);
  }
  .pulse { outline: 0; box-shadow: 0 0 0 8px rgba(255,255,255,0.18); }
''';

// ----- JS injected into the WebView -----
const String _relatedJs = '''
  (function(){
    function setup(){
      const mv = document.querySelector('model-viewer');
      if(!mv) return;
      document.querySelectorAll('button.hotspot').forEach(btn => {
        btn.addEventListener('click', () => {
          if (typeof Hotspot !== 'undefined' && Hotspot.postMessage) {
            Hotspot.postMessage(btn.dataset.id);
          }
        });
      });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup);
    else setup();

    // Expose a helper to move the camera to a given hotspot
    window.focusHotspot = function(id){
      const mv = document.querySelector('model-viewer');
      const el = document.querySelector('button.hotspot[data-id="'+id+'"]');
      if(!mv || !el) return;
      const pos = el.getAttribute('data-position');
      mv.cameraTarget = pos;
      mv.jumpCameraToGoal();
      el.classList.add('pulse');
      setTimeout(()=>el.classList.remove('pulse'), 1200);
    };
  })();
''';

// ===== Simple Exercises Page =====
class ExerciseListPage extends StatelessWidget {
  final String muscleId;
  final String muscleName;
  final List<String> exercises;
  const ExerciseListPage({
    super.key,
    required this.muscleId,
    required this.muscleName,
    required this.exercises,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$muscleName Exercises')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemBuilder: (_, i) {
          final name = exercises[i];
          return ListTile(
            leading: const Icon(Icons.fitness_center),
            title: Text(name),
            subtitle: Text('Target: $muscleName'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: push into your detailed exercise page, videos, images, etc.
            },
          );
        },
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemCount: exercises.length,
      ),
    );
  }
}
