(function() {
  var IndexModel, N1qlIndexesChecker, N1qlQuery, async, _;

  N1qlQuery = require("couchbase").N1qlQuery;

  async = require("async");

  _ = require("underscore");

  IndexModel = require("./IndexModel");


  /*
   * @method N1qlIndexesChecker
   * @description Check if required indexes exists and create them if not
   * @param {object} bucket - Couchbase bucket object
   * @param {array} wantedIndexes - Indexes required
   * @param {callback} cb - Callback
   */

  module.exports = N1qlIndexesChecker = function(bucket, wantedIndexes, cb) {
    var currentIndexes;
    wantedIndexes.unshift({
      name: "#primary",
      is_primary: true,
      using: "GSI",
      index_key: []
    });
    currentIndexes = [];
    tasks.push(function(aCb) {
      N1qlQuery.fromString("SELECT indexes.* FROM system:indexes WHERE keyspace_id=" + bucket.name + " USING GSI;");
      return bucket.query(query, function(err, results) {
        var createIndexes;
        if (err != null) {
          aCb(err);
          return;
        }
        wantedIndexes = _.map(wantedIndexes, function(index) {
          return new IndexModel(index.name, index.is_primary, index.using, index.index_key);
        });
        currentIndexes = _.map(results.results, function(index) {
          return new IndexModel(index.name, index.is_primary, index.using, index.index_key);
        });
        createIndexes = _.union(wantedIndexes, currentIndexes);
        return aCb();
      });
    });
    tasks.push(function(aCb) {
      var index, querys, _i, _len, _sendIndexQuery;
      querys = [];
      for (_i = 0, _len = createIndexes.length; _i < _len; _i++) {
        index = createIndexes[_i];
        if (index.is_primary) {
          querys.push(N1qlQuery.fromString("CREATE PRIMARY INDEX ON `" + (bucket.name()) + "` USING " + index.using + ";"));
        } else {
          querys.push(N1qlQuery.fromString("CREATE `" + index.name + "` ON `" + (bucket.name()) + "` (" + (index.index_key.join(", ")) + ") USING " + index.using + ";"));
        }
      }
      _sendIndexQuery = function(query, indexCb) {
        return bucket.query(query, function(err, results) {
          if (err != null) {
            throw err;
          }
          return indexCb();
        });
      };
      return async.map(querys, _sendIndexQuery, function(err) {
        if (err != null) {
          aCb(err);
          return;
        }
        return aCb();
      });
    });
    return async.series(tasks, function(err) {
      if (err != null) {
        cb(err);
        return;
      }
      return cb();
    });
  };

}).call(this);
