class Opensearch < Formula
  desc "Open source distributed and RESTful search engine"
  homepage "https://github.com/opensearch-project/OpenSearch"
  url "https://github.com/opensearch-project/OpenSearch/archive/refs/tags/2.19.1.tar.gz"
  sha256 "99999a392dcf90bafebfa143ed071b45662fb022dcbcfa77df802248338d3a63"
  license "Apache-2.0"

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "8d9bc85686873309e2c833c02b55bbf5e63b089dbcaee566ffd84b10262e1954"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "bfd6cf96d7dba6abaf0cd69917e9311a8740b04330e243c3f87aec20e48416ab"
    sha256 cellar: :any_skip_relocation, arm64_ventura: "debb7647524b1ca23c9cb4fa0d5a1431e49035baa80f243131154c3b165b8b0f"
    sha256 cellar: :any_skip_relocation, sonoma:        "e77aa0a76c1b17743a4be02964eb0d264f9d98b359d9c8e839832cebb1ec14ed"
    sha256 cellar: :any_skip_relocation, ventura:       "18331d741ec1f4db20654bd6d8afe8d047ad22273b83a1c8f856433ef097235e"
    sha256 cellar: :any_skip_relocation, x86_64_linux:  "4aa5a2d8dc6ac88a1543047d88c4823d512d5de672ed48dd0d22484bfcdb97fe"
  end

  depends_on "gradle" => :build
  depends_on "openjdk"

  # Fix for gradle 8.13, could be removed in the next release
  # We modify the patch to remove binary changes for linux
  # PR Ref: https://github.com/opensearch-project/OpenSearch/pull/17345
  patch :DATA

  def install
    platform = OS.kernel_name.downcase
    platform += "-arm64" if Hardware::CPU.arm?
    system "gradle", "-Dbuild.snapshot=false", ":distribution:archives:no-jdk-#{platform}-tar:assemble"

    mkdir "tar" do
      # Extract the package to the tar directory
      system "tar", "--strip-components=1", "-xf",
        Dir["../distribution/archives/no-jdk-#{platform}-tar/build/distributions/opensearch-*.tar.gz"].first

      # Install into package directory
      libexec.install "bin", "lib", "modules"

      # Set up Opensearch for local development:
      inreplace "config/opensearch.yml" do |s|
        # 1. Give the cluster a unique name
        s.gsub!(/#\s*cluster\.name: .*/, "cluster.name: opensearch_homebrew")

        # 2. Configure paths
        s.sub!(%r{#\s*path\.data: /path/to.+$}, "path.data: #{var}/lib/opensearch/")
        s.sub!(%r{#\s*path\.logs: /path/to.+$}, "path.logs: #{var}/log/opensearch/")
      end

      inreplace "config/jvm.options", %r{logs/gc.log}, "#{var}/log/opensearch/gc.log"

      # add placeholder to avoid removal of empty directory
      touch "config/jvm.options.d/.keepme"

      # Move config files into etc
      (etc/"opensearch").install Dir["config/*"]
    end

    inreplace libexec/"bin/opensearch-env",
              "if [ -z \"$OPENSEARCH_PATH_CONF\" ]; then OPENSEARCH_PATH_CONF=\"$OPENSEARCH_HOME\"/config; fi",
              "if [ -z \"$OPENSEARCH_PATH_CONF\" ]; then OPENSEARCH_PATH_CONF=\"#{etc}/opensearch\"; fi"

    bin.install libexec/"bin/opensearch",
                libexec/"bin/opensearch-keystore",
                libexec/"bin/opensearch-plugin",
                libexec/"bin/opensearch-shard"
    bin.env_script_all_files(libexec/"bin", JAVA_HOME: Formula["openjdk"].opt_prefix)
  end

  def post_install
    # Make sure runtime directories exist
    (var/"lib/opensearch").mkpath
    (var/"log/opensearch").mkpath
    ln_s etc/"opensearch", libexec/"config" unless (libexec/"config").exist?
    (var/"opensearch/plugins").mkpath
    ln_s var/"opensearch/plugins", libexec/"plugins" unless (libexec/"plugins").exist?
    (var/"opensearch/extensions").mkpath
    ln_s var/"opensearch/extensions", libexec/"extensions" unless (libexec/"extensions").exist?
    # fix test not being able to create keystore because of sandbox permissions
    system bin/"opensearch-keystore", "create" unless (etc/"opensearch/opensearch.keystore").exist?
  end

  def caveats
    <<~EOS
      Data:    #{var}/lib/opensearch/
      Logs:    #{var}/log/opensearch/opensearch_homebrew.log
      Plugins: #{var}/opensearch/plugins/
      Config:  #{etc}/opensearch/
    EOS
  end

  service do
    run opt_bin/"opensearch"
    working_dir var
    log_path var/"log/opensearch.log"
    error_log_path var/"log/opensearch.log"
  end

  test do
    port = free_port
    (testpath/"data").mkdir
    (testpath/"logs").mkdir
    fork do
      exec bin/"opensearch", "-Ehttp.port=#{port}",
                             "-Epath.data=#{testpath}/data",
                             "-Epath.logs=#{testpath}/logs"
    end
    sleep 60
    output = shell_output("curl -s -XGET localhost:#{port}/")
    assert_equal "opensearch", JSON.parse(output)["version"]["distribution"]

    system bin/"opensearch-plugin", "list"
  end
end

__END__
diff --git a/build.gradle b/build.gradle
index 679f7b9299248fb0f5173db8fccdfb77965e394b..187574da9e62aec063548871f5dc1a7fbf62a082 100644
--- a/build.gradle
+++ b/build.gradle
@@ -721,7 +721,7 @@ subprojects {
 reporting {
   reports {
     testAggregateTestReport(AggregateTestReport) {
-      testType = TestSuiteType.UNIT_TEST
+      testSuiteName = "test"
     }
   }
 }
diff --git a/distribution/packages/build.gradle b/distribution/packages/build.gradle
index ada19dfa38e785aed9ea01d613226d624856ebbd..d3cecde24a35dade98ed18c2d5f55dba0ee5b5b7 100644
--- a/distribution/packages/build.gradle
+++ b/distribution/packages/build.gradle
@@ -63,7 +63,7 @@ import java.util.regex.Pattern
  */
 
 plugins {
-  id "com.netflix.nebula.ospackage-base" version "11.10.1"
+  id "com.netflix.nebula.ospackage-base" version "11.11.1"
 }
 
 void addProcessFilesTask(String type, boolean jdk) {
diff --git a/gradle/code-coverage.gradle b/gradle/code-coverage.gradle
index eb27dd1a76634251bceafd6fefbafd65eafd5c66..1e41f12e1cc48de3ec9bcd0078f348f3a30af8f3 100644
--- a/gradle/code-coverage.gradle
+++ b/gradle/code-coverage.gradle
@@ -38,7 +38,7 @@ if (System.getProperty("tests.coverage")) {
   reporting {
     reports {
       testCodeCoverageReport(JacocoCoverageReport) {
-        testType = TestSuiteType.UNIT_TEST
+        testSuiteName = "test"
       }
     }
   }
diff --git a/gradle/wrapper/gradle-wrapper.properties b/gradle/wrapper/gradle-wrapper.properties
index c51246f2815f5294bd8a51b3ac25c19964577ac1..95e1a2f213a063c0f371f4eab8e67ba860be7baa 100644
--- a/gradle/wrapper/gradle-wrapper.properties
+++ b/gradle/wrapper/gradle-wrapper.properties
@@ -11,7 +11,7 @@
 
 distributionBase=GRADLE_USER_HOME
 distributionPath=wrapper/dists
-distributionUrl=https\://services.gradle.org/distributions/gradle-8.12.1-all.zip
+distributionUrl=https\://services.gradle.org/distributions/gradle-8.13-all.zip
 zipStoreBase=GRADLE_USER_HOME
 zipStorePath=wrapper/dists
-distributionSha256Sum=296742a352f0b20ec14b143fb684965ad66086c7810b7b255dee216670716175
+distributionSha256Sum=fba8464465835e74f7270bbf43d6d8a8d7709ab0a43ce1aa3323f73e9aa0c612
diff --git a/gradlew b/gradlew
index f5feea6d6b116baaca5a2642d4d9fa1f47d574a7..faf93008b77e7b52e18c44e4eef257fc2f8fd76d 100755
--- a/gradlew
+++ b/gradlew
@@ -86,8 +86,7 @@ done
 # shellcheck disable=SC2034
 APP_BASE_NAME=${0##*/}
 # Discard cd standard output in case $CDPATH is set (https://github.com/gradle/gradle/issues/25036)
-APP_HOME=$( cd -P "${APP_HOME:-./}" > /dev/null && printf '%s
-' "$PWD" ) || exit
+APP_HOME=$( cd -P "${APP_HOME:-./}" > /dev/null && printf '%s\n' "$PWD" ) || exit
 
 # Use the maximum available, or set MAX_FD != -1 to use that value.
 MAX_FD=maximum
@@ -206,7 +205,7 @@ fi
 DEFAULT_JVM_OPTS='"-Xmx64m" "-Xms64m"'
 
 # Collect all arguments for the java command:
-#   * DEFAULT_JVM_OPTS, JAVA_OPTS, JAVA_OPTS, and optsEnvironmentVar are not allowed to contain shell fragments,
+#   * DEFAULT_JVM_OPTS, JAVA_OPTS, and optsEnvironmentVar are not allowed to contain shell fragments,
 #     and any embedded shellness will be escaped.
 #   * For example: A user cannot expect ${Hostname} to be expanded, as it is an environment variable and will be
 #     treated as '${Hostname}' itself on the command line.
