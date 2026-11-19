const { withGradleProperties } = require("expo/config-plugins");

module.exports = function withBuildConfig(config) {
  return withGradleProperties(config, (cfg) => {
    const key = "android.defaults.buildfeatures.buildconfig";
    const existing = cfg.modResults.find(
      (item) => item.type === "property" && item.key === key,
    );
    if (existing) {
      existing.value = "true";
    } else {
      cfg.modResults.push({
        type: "property",
        key,
        value: "true",
      });
    }
    return cfg;
  });
};
