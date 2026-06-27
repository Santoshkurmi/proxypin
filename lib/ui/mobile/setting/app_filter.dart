/*
 * Copyright 2023 Hongen Wang
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/native/installed_apps.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/utils/task.dart';

///应用白名单 目前只支持安卓 ios没办法获取安装的列表
///@author wang
class AppWhitelist extends StatefulWidget {
  final ProxyServer proxyServer;

  const AppWhitelist({super.key, required this.proxyServer});

  @override
  State<AppWhitelist> createState() => _AppWhitelistState();
}

class _AppWhitelistState extends State<AppWhitelist> {
  late Configuration configuration;
  bool changed = false;
  final List<AppInfo> _apps = [];
  bool _loaded = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    configuration = widget.proxyServer.configuration;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadApps());
  }

  Future<void> _loadApps() async {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
    var unknown = isCN ? "未知应用" : "Unknown app";

    if (Platform.isAndroid) {
      var results = await InstalledApps.getAppInfoBatch(configuration.appWhitelist);
      for (var info in results) {
        if (info.name == null || info.name!.isEmpty) {
          info.name = unknown;
          info.inValid = true;
        }
        _apps.add(info);
        if (mounted) setState(() {});
      }
    } else {
      for (var pkg in configuration.appWhitelist) {
        var info = await InstalledApps.getAppInfo(pkg)
            .timeout(const Duration(seconds: 10))
            .catchError((_) => AppInfo(name: unknown, packageName: pkg, inValid: true));
        _apps.add(info);
        if (mounted) setState(() {});
      }
    }

    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    if (changed) {
      configuration.flushConfig();
      if (Vpn.isVpnStarted) {
        Vpn.restartVpn("127.0.0.1", widget.proxyServer.port, configuration);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return Scaffold(
        appBar: AppBar(
          title: Text(localizations.appWhitelist, style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                if (!context.mounted) return;
                var info = await Navigator.of(context).push<AppInfo>(
                    MaterialPageRoute(builder: (_) => InstalledAppsWidget(addedList: _apps)));
                if (info == null || configuration.appWhitelist.contains(info.packageName)) return;
                configuration.appWhitelist.add(info.packageName!);
                changed = true;
                if (mounted) setState(() => _apps.add(info));
              },
            ),
            IconButton(
              tooltip: isCN ? '清除失效应用' : 'clear invalid apps',
              onPressed: () {
                if (_apps.isEmpty || configuration.appWhitelist.isEmpty) return;
                for (var appInfo in _apps) {
                  if (appInfo.inValid == true) {
                    configuration.appWhitelist.remove(appInfo.packageName);
                  }
                }
                setState(() {
                  _apps.removeWhere((a) => a.inValid == true);
                  changed = true;
                });
              },
              icon: Icon(Icons.cleaning_services_outlined),
            ),
          ],
        ),
        body: Column(children: [
          const SizedBox(height: 5),
          SwitchWidget(
              value: configuration.appWhitelistEnabled,
              title: localizations.enable,
              subtitle: localizations.appWhitelistDescribe,
              onChanged: (val) {
                changed = true;
                configuration.appWhitelistEnabled = val;
                configuration.flushConfig();
              }),
          const SizedBox(height: 5),
          Expanded(child: _buildList(isCN))]));
  }

  Widget _buildList(bool isCN) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_apps.isEmpty) {
      return Center(
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Text(
                isCN
                    ? "未设置白名单应用时会对所有应用抓包"
                    : "When no whitelist application is set, all applications will be captured",
                style: const TextStyle(color: Colors.grey))),
      );
    }

    return ListView.builder(
        itemCount: _apps.length,
        itemBuilder: (BuildContext context, int index) {
          AppInfo appInfo = _apps[index];
          return ListTile(
            leading: _appIcon(appInfo),
            title: Text(appInfo.name ?? ""),
            subtitle: Text(appInfo.packageName ?? ""),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                configuration.appWhitelist.remove(appInfo.packageName);
                changed = true;
                setState(() => _apps.removeAt(index));
              },
            ),
          );
        });
  }

  Widget _appIcon(AppInfo appInfo) {
    var icon = appInfo.icon;
    if (icon == null || icon.isEmpty) return const Icon(Icons.question_mark);
    return Image.memory(icon, width: 24, height: 24, cacheWidth: 72, cacheHeight: 72);
  }
}

class AppBlacklist extends StatefulWidget {
  final ProxyServer proxyServer;

  const AppBlacklist({super.key, required this.proxyServer});

  @override
  State<AppBlacklist> createState() => _AppBlacklistState();
}

class _AppBlacklistState extends State<AppBlacklist> {
  late Configuration configuration;
  bool changed = false;
  final List<AppInfo> _apps = [];
  bool _loaded = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    configuration = widget.proxyServer.configuration;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadApps());
  }

  Future<void> _loadApps() async {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
    var unknown = isCN ? "未知应用" : "Unknown app";

    var packages = configuration.appBlacklist ?? [];
    if (Platform.isAndroid) {
      var results = await InstalledApps.getAppInfoBatch(packages);
      for (var info in results) {
        if (info.name == null || info.name!.isEmpty) {
          info.name = unknown;
          info.inValid = true;
        }
        _apps.add(info);
        if (mounted) setState(() {});
      }
    } else {
      for (var pkg in packages) {
        var info = await InstalledApps.getAppInfo(pkg)
            .timeout(const Duration(seconds: 10))
            .catchError((_) => AppInfo(name: unknown, packageName: pkg, inValid: true));
        _apps.add(info);
        if (mounted) setState(() {});
      }
    }

    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    if (changed) {
      configuration.flushConfig();
      if (Vpn.isVpnStarted) {
        Vpn.restartVpn("127.0.0.1", widget.proxyServer.port, configuration);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.appBlacklist, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
              onPressed: () async {
                if (!context.mounted) return;
                var info = await Navigator.of(context).push<AppInfo>(
                    MaterialPageRoute(builder: (_) => InstalledAppsWidget(addedList: _apps)));
                if (info == null || configuration.appBlacklist?.contains(info.packageName) == true) return;
                configuration.appBlacklist ??= [];
                configuration.appBlacklist!.add(info.packageName!);
                changed = true;
                if (mounted) setState(() => _apps.add(info));
              },
          ),
          IconButton(
            tooltip: isCN ? '清除失效应用' : 'clear invalid apps',
            onPressed: () {
              if (_apps.isEmpty || configuration.appBlacklist?.isEmpty == true) return;
              for (var appInfo in _apps) {
                if (appInfo.inValid == true) {
                  configuration.appBlacklist?.remove(appInfo.packageName);
                }
              }
              setState(() {
                _apps.removeWhere((a) => a.inValid == true);
                changed = true;
              });
            },
            icon: Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: _buildList(isCN),
    );
  }

  Widget _buildList(bool isCN) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_apps.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Text(localizations.emptyData, style: const TextStyle(color: Colors.grey))));
    }

    return ListView.builder(
        itemCount: _apps.length,
        itemBuilder: (BuildContext context, int index) {
          AppInfo appInfo = _apps[index];
          return ListTile(
            leading: _appIcon(appInfo),
            title: Text(appInfo.name ?? ""),
            subtitle: Text(appInfo.packageName ?? ""),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                configuration.appBlacklist?.remove(appInfo.packageName);
                changed = true;
                setState(() => _apps.removeAt(index));
              },
            ),
          );
        });
  }

  Widget _appIcon(AppInfo appInfo) {
    var icon = appInfo.icon;
    if (icon == null || icon.isEmpty) return const Icon(Icons.question_mark);
    return Image.memory(icon, width: 24, height: 24, cacheWidth: 72, cacheHeight: 72);
  }
}

///已安装的app列表
class InstalledAppsWidget extends StatefulWidget {
  const InstalledAppsWidget({
    super.key,
    required this.addedList,
  });

  final List<AppInfo> addedList;

  @override
  State<InstalledAppsWidget> createState() => _InstalledAppsWidgetState();
}

class _InstalledAppsWidgetState extends State<InstalledAppsWidget> {
  static List<AppInfo>? apps;
  static bool includeSystemApps = false;
  static final Map<String, Future<AppInfo>> _iconFutureCache = {};

  RxBool loading = false.obs;

  String? keyword;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refreshApps());
  }

  @override
  void dispose() {
    DelayedTask().debounce("InstalledAppsWidget_release", const Duration(seconds: 60), () {
      apps = null;
      includeSystemApps = false;
      _iconFutureCache.clear();
    });
    super.dispose();
  }

  void refreshApps() async {
    try {
      loading.value = true;
      apps = await InstalledApps.getInstalledApps(false, includeSystemApps: includeSystemApps);
    } finally {
      loading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: InputDecoration(
            hintText: isCN ? "请输入应用名或包名" : "Please enter the application or package name",
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey.shade500),
            suffixIcon: IconButton(
              color: includeSystemApps ? Theme.of(context).colorScheme.primary : null,
              icon: const Icon(Icons.visibility_outlined),
              tooltip: isCN ? "显示系统应用" : "Show system apps",
              onPressed: () {
                setState(() {
                  includeSystemApps = !includeSystemApps;
                });
                refreshApps();
              },
            ),
          ),
          onChanged: (String value) {
            keyword = value.toLowerCase();
            setState(() {});
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshApps();
        },
        child: Obx(() => loading.value
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : buildAppListView()),
      ),
    );
  }

  ListView buildAppListView() {
    if (apps == null) {
      return ListView();
    }
    List<AppInfo> appInfoList = apps!;
    appInfoList = appInfoList.toSet().difference(widget.addedList.toSet()).toList();
    if (keyword != null && keyword!.trim().isNotEmpty) {
      appInfoList = appInfoList
          .where((element) =>
              element.name!.toLowerCase().contains(keyword!) || element.packageName!.toLowerCase().contains(keyword!))
          .toList();
    }

    return ListView.builder(
        itemCount: appInfoList.length,
        itemBuilder: (BuildContext context, int index) {
          AppInfo appInfo = appInfoList[index];
          return ListTile(
            leading: _buildAppIcon(appInfo),
            title: Text(appInfo.name ?? ""),
            subtitle: Text(appInfo.packageName ?? ""),
            onTap: () async {
              var info = await InstalledApps.getAppInfo(appInfo.packageName!)
                  .timeout(const Duration(seconds: 5))
                  .catchError((_) => appInfo);
              if (context.mounted) Navigator.of(context).pop(info);
            },
          );
        });
  }

  Widget _buildAppIcon(AppInfo appInfo) {
    final icon = appInfo.icon;
    if (icon != null && icon.isNotEmpty) {
      return Image.memory(icon, width: 24, height: 24, cacheWidth: 72, cacheHeight: 72);
    }

    final packageName = appInfo.packageName;
    if (packageName == null || packageName.isEmpty) {
      return const Icon(Icons.question_mark);
    }

    final future = _iconFutureCache.putIfAbsent(
      packageName,
      () => InstalledApps.getAppInfo(packageName),
    );

    return FutureBuilder<AppInfo>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<AppInfo> snapshot) {
        final loadedIcon = snapshot.data?.icon;
        if (loadedIcon != null && loadedIcon.isNotEmpty) {
          return Image.memory(loadedIcon, width: 24, height: 24, cacheWidth: 72, cacheHeight: 72);
        }

        if (snapshot.hasError) {
          return const Icon(Icons.question_mark);
        }

        return const SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}
