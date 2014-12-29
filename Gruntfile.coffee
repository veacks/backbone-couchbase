'use strict';
module.exports = (grunt) ->
  require('grunt-config-dir')(grunt, {
    configDir: require('path').resolve('tasks')
  })
  
  grunt.registerTask 'test', ['mochacli']
  grunt.registerTask 'build', ['coffee']