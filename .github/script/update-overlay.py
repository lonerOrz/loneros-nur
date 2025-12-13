#!/usr/bin/env python3
"""
专门用于更新 overlays 中定义的软件的脚本
严格按照以下流程执行：
1. 获取更新列表（通过读取 overlays/default.nix）
2. 获取更新脚本的drv
3. 使用 nix build 构建具体脚本
4. 运行脚本
"""

import subprocess
import argparse
import json
import re
import os
from pathlib import Path

EXCLUDE_PACKAGES = ["Utils", "generic-git-update", "rustc_latest"]

def get_overlay_packages():
    """通过 Nix eval 获取 overlay 中定义的包列表"""
    try:
        # 使用 Nix eval 来获取 overlay 中定义的包
        result = subprocess.run(
            [
                "nix", "eval", "--impure", "--json",
                "--expr",
                'let flakes = { self = ./.; nixpkgs = <nixpkgs>; }; '
                'overlaysFun = import ./overlays/default.nix { inherit flakes; '
                'selfOverlay = import ./overlays/default.nix { inherit flakes; }; }; '
                f'exclude = {EXCLUDE_PACKAGES}; in '
                'builtins.filter (name: ! builtins.elem name exclude) (builtins.attrNames (overlaysFun {} {}))'
            ],
            capture_output=True,
            text=True,
            check=True
        )
        packages = json.loads(result.stdout)
        return packages
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Failed to eval overlay packages: {e.stderr}")
        return []


def get_update_script_drv_path(pkg_name):
    """获取更新脚本的drv路径"""
    # 从 legacyPackages 获取 overlay 包的 updateScript
    try:
        result = subprocess.run(
            [
                "nix",
                "eval",
                f".#{pkg_name}.passthru.updateScript.drvPath",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        script_path = json.loads(result.stdout)
        return script_path
    except subprocess.CalledProcessError:
        return None


def build_update_script_and_get_path(drv_path):
    """构建更新脚本并返回其路径，由调用者负责清理"""
    import tempfile

    # 创建临时目录，但不使用 with 语句，让调用者负责清理
    tmpdir = tempfile.mkdtemp()
    result_path = f"{tmpdir}/result"

    # 使用 nix build 和 ^* 语法来构建 drv 及其所有输出
    result_build = subprocess.run(
        ["nix", "build", f"{drv_path}^*", "-o", result_path, "--impure"],
        capture_output=True,
        text=True,
        # 移除 check=True 以处理异常情况
        cwd=Path.cwd()
    )

    # 检查命令是否成功
    if result_build.returncode != 0:
        import shutil
        shutil.rmtree(tmpdir)  # 清理临时目录
        return None

    built_script_path = Path(result_path)
    if built_script_path.exists():
        return built_script_path
    else:
        import shutil
        shutil.rmtree(tmpdir)  # 清理临时目录
        return None


def run_update_script(script_path):
    """运行构建好的更新脚本"""
    if script_path and script_path.exists():
        print(f"[RUNNING UPDATE SCRIPT] {script_path}")
        try:
            result = subprocess.run([str(script_path)], check=True, cwd=Path.cwd())
            return result.returncode == 0
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Failed to run update script: {e}")
            return False
    else:
        print(f"[ERROR] Update script does not exist: {script_path}")
        return False


def update_overlay_package(pkg_name):
    """更新单个 overlay 包"""
    print(f"[INFO] Processing package: {pkg_name}")

    # 1. 获取更新脚本的drv路径
    drv_path = get_update_script_drv_path(pkg_name)
    if not drv_path:
        print(f"[SKIP] {pkg_name}: No updateScript found")
        return False

    print(f"[INFO] Found update script drv: {drv_path}")

    # 2. 构建更新脚本
    built_script = build_update_script_and_get_path(drv_path)
    if not built_script:
        print(f"[FAIL] {pkg_name}: Failed to build update script")
        return False

    try:
        # 3. 运行更新脚本
        success = run_update_script(built_script)
        if success:
            print(f"[OK] {pkg_name} updated successfully")
            return True
        else:
            print(f"[FAIL] {pkg_name}: Update script failed")
            return False
    finally:
        # 4. 清理临时目录
        import shutil
        from pathlib import Path
        temp_dir = built_script.parent  # 获取临时目录路径
        if temp_dir.exists():
            shutil.rmtree(temp_dir)


def main():
    parser = argparse.ArgumentParser(description="Update Nix overlay packages")
    parser.add_argument("--package", help="Update a single overlay package")
    args = parser.parse_args()

    if args.package:
        update_overlay_package(args.package)
    else:
        packages = get_overlay_packages()
        if not packages:
            print("[ERROR] No overlay packages found via Nix eval.")
            return

        print(f"Found {len(packages)} overlay packages to update from Nix eval: {', '.join(packages)}")
        for pkg in packages:
            update_overlay_package(pkg)


if __name__ == "__main__":
    main()
