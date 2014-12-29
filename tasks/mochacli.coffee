"use strict"
module.exports = mochacli = (grunt) ->
  
  # Load task
  grunt.loadNpmTasks "grunt-mocha-cli"
  
  # Options
  {
    options:
      timeout: 6000
      "check-leaks": true
      ui: "bdd"
      reporter: "spec"
      compilers: ["coffee:coffee-script/register"]
    src: ["spec/**/*.coffee"]
  }