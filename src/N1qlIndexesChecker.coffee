N1qlQuery = require("couchbase").N1qlQuery
async = require "async"
_ = require "underscore"

IndexModel = require "./IndexModel"

###
# @method N1qlIndexesChecker
# @description Check if required indexes exists and create them if not
# @param {object} bucket - Couchbase bucket object
# @param {array} wantedIndexes - Indexes required
# @param {callback} cb - Callback
###
module.exports = N1qlIndexesChecker = (bucket, wantedIndexes, cb) ->
  # Add the premary index by default
  wantedIndexes.unshift
    name: "#primary"
    is_primary: true
    using: "GSI"
    index_key: []

  currentIndexes = []

  # Get the current indexes
  tasks.push (aCb) ->
    # Querry to select all indexes in the bucket
    N1qlQuery.fromString "SELECT indexes.* FROM system:indexes WHERE keyspace_id=#{bucket.name} USING GSI;"

    # Launch query
    bucket.query query, (err, results) ->
      if err?
        aCb err
        return

      # Format indexes with index class
      wantedIndexes = _.map wantedIndexes, (index) ->
        return new IndexModel index.name, index.is_primary, index.using, index.index_key

      # Format current indexes with index class
      currentIndexes = _.map results.results, (index) ->
        return new IndexModel index.name, index.is_primary, index.using, index.index_key

      # remove all duplicates from the two arrays
      createIndexes = _.union wantedIndexes, currentIndexes
      aCb()

  # create indexes
  tasks.push (aCb) ->
    querys = []

    # Create INDEX Query for each index to create
    for index in createIndexes
      if index.is_primary
        querys.push N1qlQuery.fromString "CREATE PRIMARY INDEX ON `#{bucket.name()}` USING #{index.using};"
      else
        querys.push N1qlQuery.fromString "CREATE `#{index.name}` ON `#{bucket.name()}` (#{index.index_key.join(", ")}) USING #{index.using};"

    _sendIndexQuery = (query, indexCb) ->
      bucket.query query, (err, results) ->
        throw err if err?
        indexCb()

    # Run all index querys
    async.map querys, _sendIndexQuery, (err) ->
      if err?
        aCb err
        return
      aCb()

  # Run all index tasks
  async.series tasks, (err) ->
    if err?
      cb err
      return
    cb()