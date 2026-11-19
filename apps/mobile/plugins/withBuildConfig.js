const { withProjectBuildGradle } = require("expo/config-plugins");

const MARKER = "// withBuildConfig-react-native-bluetooth-classic";

module.exports = function withBuildConfig(config) {
  return withProjectBuildGradle(config, (cfg) => {
    if (cfg.modResults.language !== "groovy") {
      return cfg;
    }
    if (cfg.modResults.contents.includes(MARKER)) {
      return cfg;
    }

    const snippet = `
${MARKER}
subprojects { subproject ->
  if (subproject.name == 'react-native-bluetooth-classic') {
    subproject.pluginManager.withPlugin('com.android.library') {
      subproject.android {
        buildFeatures {
          buildConfig = true
        }
      }
    }
  }
}
`;

    cfg.modResults.contents = `${cfg.modResults.contents}\n${snippet}`;
    return cfg;
  });
};
