(function() {
  var Q, ViewQuery, couchbase, uuid, _;

  Q = require("q");

  uuid = require("node-uuid");

  couchbase = require("couchbase");

  ViewQuery = couchbase.ViewQuery;

  _ = require("underscore");


  /*
   * Create a Couchbase Sync Method for Backbone Models and Collections
   * @param {object} [options={}] - Options for the creation of the sync method
   * @option {object} bucket - Bucket object for the synchronisation
   * @option {object} connection - Cluster address, bucket name and password
   * @option {string} [sep="::"] - Replace "/" by separator, if false the url wont be formated
   * @option {boolean} [httpError=false] - Format couchbase error to http friendly status
   * @return {function} Backbone Couchbase Sync function
   */

  module.exports = function(options) {
    var bucket, cluster, httpError, idGen, sep, _couchbaseErrorFormat, _keyFormat;
    if (options == null) {
      options = {};
    }
    if (!((options.bucket != null) || (options.connection != null))) {
      throw new Error("Bucket or Connection object is required to generate sync method");
    }
    if (options.bucket != null) {
      bucket = options.bucket;
    } else if (options.connection != null) {
      if (!((options.connection.cluster != null) && (options.connection.bucket != null))) {
        throw new Error("Connection bucket and cluster are required");
      }
      cluster = new couchbase.Cluster(options.connection.cluster);
      if (options.connection.password != null) {
        bucket = cluster.openBucket(options.connection.bucket, options.connection.password);
      } else {
        bucket = cluster.openBucket(options.connection.bucket);
      }
    }
    httpError = options.httpError || true;
    sep = options.sep || "::";
    idGen = options.idGen || uuid;

    /*
     * Format the document key
     * @private
     */
    _keyFormat = function(url) {
      if (!sep) {
        return url;
      }
      url = decodeURIComponent(url);
      url = url.replace(/^(\/)/, '');
      return url = url.replace(/\//g, sep);
    };

    /*
     * Format couchbase error to http friendly
     * @private
     */
    _couchbaseErrorFormat = function(error) {
      if (!httpError) {
        return error;
      }
      switch (error.toString()) {
        case "Error: key does not exist":
          return {
            status: 404,
            message: error
          };
        case "Error: key already exists":
          return {
            status: 409,
            message: error
          };
        default:
          return {
            status: 500,
            message: error
          };
      }
    };

    /*
     * Generate the Backbone Sync Method
     * @param {string} method - CRUD command
     * @param {object} model - Backbone Model or Collection object
     * @param {object} options - Sync options
     * @option {callback~Error} error - Callback error
     * @option {callback~Success} success - Callback success 
     * @option {boolean} trace - Trace Couchbase process
     * @option {boolean} create - Force creation with a specific key 
     * @return promise
     */
    return function(method, model, options) {
      var couchbase_callback, def, query;
      def = Q.defer();
      couchbase_callback = function(err, result) {
        var response, _i, _len;
        if (options.trace) {
          console.log("-----");
          console.log("Backbone Couchbase:");
          console.log("  - method:");
          console.log(method);
          console.log("  - id:");
          console.log(_keyFormat(model.url()));
          console.log(options);
        }
        if (err != null) {
          if ((options != null) && (options.error != null)) {
            options.error(_couchbaseErrorFormat(err));
          }
          def.reject(_couchbaseErrorFormat(err));
          if (options.trace) {
            console.log("  - err:");
            console.log(err);
          }
          return false;
        }
        if (_.isArray(result)) {
          response = [];
          for (_i = 0, _len = result.length; _i < _len; _i++) {
            model = result[_i];
            response.push(model.value);
          }
        } else {
          response = result.value;
        }
        if ((options != null) && (options.success != null)) {
          options.success(response);
        }
        def.resolve(response);
        if (options.trace) {
          console.log("  - response:");
          console.log(response);
          return console.log("-----");
        }
      };
      if (method === "create" || ((options.create != null) && options.create)) {
        if (model.isNew()) {
          model.set(model.idAttribute, uuid.v4());
        }
        bucket.insert(_keyFormat(model.url()), model.toJSON(), function(err, result) {
          if (err != null) {
            couchbase_callback(err, result);
            return false;
          }
          return bucket.get(_keyFormat(model.url()), couchbase_callback);
        });
      } else if (method === "update" && ((options.create == null) || !options.create)) {
        bucket.replace(_keyFormat(model.url()), model.toJSON(), function(err, result) {
          if (err != null) {
            couchbase_callback(err, result);
            return false;
          }
          return bucket.get(_keyFormat(model.url()), couchbase_callback);
        });
      } else if (method === "read") {
        if (model.models != null) {
          query = ViewQuery.from(model.url, options.viewName || model.defaultView);
          if (options.custom != null) {
            query.custom(options.custom);
          }
          bucket.query(query, couchbase_callback);
        } else {
          bucket.get(_keyFormat(model.url()), couchbase_callback);
        }
      } else if (method === "patch") {
        bucket.get(_keyFormat(model.url()), function(err, result) {
          var dbModel;
          if (err != null) {
            couchbase_callback(err, result);
            return;
          }
          dbModel = result.value;
          _.extend(dbModel, model.toJSON());
          return bucket.replace(_keyFormat(model.url()), dbModel, function(err, result) {
            if (err != null) {
              couchbase_callback(err, result);
              return false;
            }
            return bucket.get(_keyFormat(model.url()), couchbase_callback);
          });
        });
      } else if (method === "delete") {
        bucket.remove(_keyFormat(model.url()), couchbase_callback);
      } else {
        couchbase_callback({
          code: 500,
          message: "" + method + ": Wrong or empty method for Backbone-Couchbase-Sync"
        });
      }
      model.trigger('request', model, def.promise, options);
      return def.promise;
    };
  };

}).call(this);
