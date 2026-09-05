import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

/// 关于页（模块 10）：版本号、产品简介、开源许可与数据来源。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.version = '0.9.0-beta'});

  final String version;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const PixelAppBar(title: '关于', leading: BackButton()),
      body: PixelBackdrop(
        child: PixelContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              PixelPanel(
                color: scheme.primaryContainer,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const PixelIconTile(
                      icon: Icons.restaurant_outlined,
                      size: 56,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '餐盘',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v$version',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '记录每一餐，看看吃得均不均衡',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const PixelSectionHeader(
                title: '数据来源',
                icon: Icons.menu_book_outlined,
              ),
              const SizedBox(height: 10),
              PixelPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.menu_book_outlined),
                      title: Text('《中国居民膳食指南（2022）》'),
                      subtitle: Text('每日推荐份数按能量档位计算'),
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: const Icon(Icons.code),
                      title: const Text('开源许可'),
                      subtitle: const Text('cn-food-mcp · MIT 协议'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: '餐盘',
                        applicationVersion: version,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const PixelSectionHeader(
                title: '隐私与反馈',
                icon: Icons.privacy_tip_outlined,
              ),
              const SizedBox(height: 10),
              PixelPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.privacy_tip_outlined),
                      title: Text('纯本地使用'),
                      subtitle: Text('身体数据与饮食记录只保存在你的手机上'),
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: const Icon(Icons.feedback_outlined),
                      title: const Text('意见反馈'),
                      subtitle: const Text('当前为内部测试版，请通过项目 GitHub Issue 反馈'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
