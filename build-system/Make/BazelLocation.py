import os
import stat
import sys
from urllib.parse import urlparse, urlunparse
import tempfile
import hashlib
import shutil
import re

from BuildEnvironment import is_apple_silicon, resolve_executable, call_executable, run_executable_with_status, BuildEnvironmentVersions

def transform_cache_host_into_http(grpc_url):
    parsed_url = urlparse(grpc_url)
    
    new_scheme = "http"
    new_port = 8080
    
    transformed_url = urlunparse((
        new_scheme,
        f"{parsed_url.hostname}:{new_port}",
        parsed_url.path,
        parsed_url.params,
        parsed_url.query,
        parsed_url.fragment
    ))
    
    return transformed_url

def calculate_sha256(file_path):
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as file:
        # Read the file in chunks to avoid using too much memory
        for byte_block in iter(lambda: file.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def resolve_cache_host(cache_host):
    if cache_host is None:
        return None
    if cache_host.startswith("file://"):
        return None
    if "@auto" in cache_host:
        host_parts = cache_host.split("@auto")
        host_left_part = host_parts[0]
        host_right_part = host_parts[1]
        return f"{host_left_part}localhost{host_right_part}"
    return cache_host

def resolve_cache_path(cache_host_or_path, cache_dir):
    if cache_dir is not None:
        return cache_dir
    if cache_host_or_path is not None:
        if cache_host_or_path.startswith("file://"):
            return cache_host_or_path.replace("file://", "")
    return None

def cache_cas_name(digest):
    return (digest[:2], digest)

def download_bazel_release(version, name, output_path):
    """Downloads a Bazel release binary; the caller verifies its SHA256.

    The release's download link answered 504 for hours on 2026-11-08 while the GitHub API served the same asset, so a
    failed link (after curl's own retries) falls back to the API. When the API fails too, the link's error is raised:
    it is the one that says what went wrong with the usual path.
    """
    try:
        call_executable([
            'curl', '--fail', '-L', '--proto', '=https', '--proto-redir', '=https',
            '--retry', '3', '--retry-delay', '10', '--retry-all-errors',
            'https://github.com/bazelbuild/bazel/releases/download/{version}/{name}'.format(version=version, name=name),
            '--output', output_path
        ])
    except RuntimeError as link_error:
        print('Bazel release link failed ({}), trying the GitHub API'.format(link_error))
        try:
            download_bazel_release_from_api(version, name, output_path)
        except Exception as api_error:
            print('Bazel download through the GitHub API failed too: {}'.format(api_error))
            raise link_error


def download_bazel_release_from_api(version, name, output_path, attempts=5, retry_delay=10.0):
    """The release asset through api.github.com. A token from GH_TOKEN or GITHUB_TOKEN, when set, is sent to the API
    host only: the asset's redirect to the storage host does not carry it."""
    import json
    import time
    import urllib.request

    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')

    def api_request(url, accept):
        request = urllib.request.Request(url, headers={'Accept': accept, 'User-Agent': 'telegram-ios-build'})
        if token:
            request.add_unredirected_header('Authorization', 'Bearer {}'.format(token))
        return request

    last_error = None
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(api_request('https://api.github.com/repos/bazelbuild/bazel/releases/tags/{}'.format(version), 'application/vnd.github+json'), timeout=60) as response:
                release = json.load(response)
            asset_url = next(asset['url'] for asset in release['assets'] if asset['name'] == name)
            with urllib.request.urlopen(api_request(asset_url, 'application/octet-stream'), timeout=600) as response, open(output_path, 'wb') as output:
                shutil.copyfileobj(response, output)
            return
        except Exception as error:
            last_error = error
            print('Bazel download through the GitHub API failed (attempt {}): {}'.format(attempt + 1, error))
            if attempt + 1 < attempts:
                time.sleep(retry_delay)
    raise RuntimeError('Could not download {} {} through the GitHub API: {}'.format(name, version, last_error))


def locate_bazel(base_path, cache_host_or_path, cache_dir):
    build_input_dir = '{}/build-input'.format(base_path)
    if not os.path.isdir(build_input_dir):
        os.mkdir(build_input_dir)

    versions = BuildEnvironmentVersions(base_path=base_path)
    digest = versions.bazel_version_sha256
    if not isinstance(digest, str) or re.fullmatch(r'[0-9a-fA-F]{64}', digest) is None:
        raise ValueError('A valid Bazel SHA256 is required before installing an executable')
    digest = digest.lower()
    if is_apple_silicon():
        arch = 'darwin-arm64'
    else:
        arch = 'darwin-x86_64'
    bazel_name = 'bazel-{version}-{arch}'.format(version=versions.bazel_version, arch=arch)
    bazel_path = '{}/build-input/{}'.format(base_path, bazel_name)

    resolved_cache_host = resolve_cache_host(cache_host_or_path)
    resolved_cache_path = resolve_cache_path(cache_host_or_path, cache_dir)

    if os.path.isfile(bazel_path):
        if calculate_sha256(bazel_path) != digest:
            print(f"Bazel at {bazel_path} does not match SHA256 {versions.bazel_version_sha256}, removing")
            os.remove(bazel_path)

    if not os.path.isfile(bazel_path):
        # Stage on the destination filesystem: neither interrupted transfers nor
        # unverified cache entries may appear at the executable's final path.
        descriptor, staging_path = tempfile.mkstemp(prefix='.bazel-download-', dir=build_input_dir)
        os.close(descriptor)
        downloaded = False
        try:
            if resolved_cache_host is not None:
                http_cache_host = transform_cache_host_into_http(resolved_cache_host)
                call_executable([
                    'curl', '--fail', '-L',
                    '{}/cache/cas/{}'.format(http_cache_host, digest),
                    '--output', staging_path
                ], check_result=False)
            elif resolved_cache_path is not None:
                cache_cas_id, cache_cas_name_value = cache_cas_name(digest)
                cached_path = '{}/cas/{}/{}'.format(resolved_cache_path, cache_cas_id, cache_cas_name_value)
                if os.path.isfile(cached_path):
                    shutil.copyfile(cached_path, staging_path)

            if calculate_sha256(staging_path) != digest:
                download_bazel_release(versions.bazel_version, bazel_name, staging_path)
                downloaded = True
                if calculate_sha256(staging_path) != digest:
                    raise RuntimeError('Downloaded Bazel does not match the required SHA256')

            os.chmod(staging_path, os.stat(staging_path).st_mode | stat.S_IEXEC)
            os.replace(staging_path, bazel_path)
        finally:
            if os.path.exists(staging_path):
                os.remove(staging_path)

        # Only verified, successfully installed downloads may populate the cache.
        if downloaded and resolved_cache_host is not None:
            http_cache_host = transform_cache_host_into_http(resolved_cache_host)
            print(f"Uploading bazel@{versions.bazel_version_sha256} to bazel-remote")
            call_executable([
                'curl',
                '-X',
                'PUT',
                '-T',
                bazel_path,
                '{cache_host}/cache/cas/{hash}'.format(
                    cache_host=http_cache_host,
                    hash=versions.bazel_version_sha256
                )
            ], check_result=False)
        elif downloaded and resolved_cache_path is not None:
            (cache_cas_id, cache_cas_name_value) = cache_cas_name(digest)
            cached_path = '{}/cas/{}/{}'.format(resolved_cache_path, cache_cas_id, cache_cas_name_value)
            os.makedirs(os.path.dirname(cached_path), exist_ok=True)
            shutil.copyfile(bazel_path, cached_path)

    if not os.access(bazel_path, os.X_OK):
        st = os.stat(bazel_path)
        os.chmod(bazel_path, st.st_mode | stat.S_IEXEC)

    return bazel_path
