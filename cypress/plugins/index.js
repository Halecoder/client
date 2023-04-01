const { execSync } = require('child_process');
const cfg = require("../../config.js");
const hiddenCfg = require("../../hidden-config.js");

/// <reference types="cypress" />
// ***********************************************************
// This example plugins/index.js can be used to load plugins
//
// You can change the location of this file or turn off loading
// the plugins file with the 'pluginsFile' configuration option.
//
// You can read more here:
// https://on.cypress.io/plugins-guide
// ***********************************************************

// This function is called when a project is opened or re-opened (e.g. due to
// the project's config changing)

/**
 * @type {Cypress.PluginConfig}
 */
module.exports = (on, config) => {
  // `on` is used to hook into various events Cypress emits
  // `config` is the resolved Cypress config
  require('cypress-watch-and-reload/plugins');

  on('task', {
    'db:seed': ({dbName, seedName}) => {
      try {
        return execSync(`couchdb-backup -r -H "${cfg.COUCHDB_HOST}" -P "${cfg.COUCHDB_PORT}" -u "${hiddenCfg.COUCHDB_ADMIN_USERNAME}" -p "${hiddenCfg.COUCHDB_ADMIN_PASSWORD}" -d "${dbName}" -f "${__dirname}/../fixtures/${seedName}.json"`)
      } catch(e) {
        return e.toString()
      }
    }
  })
}
