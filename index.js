(function() {
  var Backbone, Q, ViewQuery, async, couchbase, uuid, _, _originalCollectionFetch;

  Q = require("q");

  uuid = require("node-uuid");

  couchbase = require("couchbase");

  ViewQuery = couchbase.ViewQuery;

  _ = require("underscore");

  async = require("async");

  Backbone = require("backbone");


  /*
   * Set up the join functionally at the Backbone Collection level
   * @param {object} [options={}] - Options for the fetch method
   */

  _originalCollectionFetch = Backbone.Collection.prototype.fetch;

  Backbone.Collection.prototype.fetch = function(options) {
    var success;
    options = options ? _.clone(options) : {};
    if ((options.join != null) && options.join === true || typeof options.join === "function") {
      success = options.success;
      options.success = (function(_this) {
        return function(resp) {
          var tasks;
          tasks = [];
          _this.each(function(model) {
            return tasks.push(function(aCb) {
              return model.fetch({
                join: options.join === true && (model.join != null) ? true : typeof options.join === "function" ? options.join : void 0,
                success: function() {
                  return aCb();
                },
                error: function(model, error) {
                  return aCb(error);
                }
              });
            });
          });
          return async.parallel(tasks, function(error) {
            if (success != null) {
              return success.call(options.context, _this, resp, options);
            }
          });
        };
      })(this);
    }
    return _originalCollectionFetch.apply(this, [options]);
  };


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
    var bucket, cluster, httpError, idGen, sep, _couchbaseErrorFormat, _keyFormat, _keysFormat;
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
     * Format the document keys
     * @private
     */
    _keysFormat = function(url, ids) {
      var id, uList, _i, _len;
      uList = [];
      for (_i = 0, _len = ids.length; _i < _len; _i++) {
        id = ids[_i];
        uList.push(_keyFormat(url + "/" + id));
      }
      return uList;
    };

    /*
     * Format the document key
     * @private
     */
    _keyFormat = function(url) {
      url = decodeURIComponent(url);
      url = url.replace(/^(\/)/, '');
      return url = url.replace(/\//g, sep);
    };

    /*
     * Format couchbase error to http friendly
     * @private
     */
    _couchbaseErrorFormat = function(error, result) {
      if (!httpError) {
        return error;
      }
      switch (error.code) {
        case 13:
          return {
            status: 404,
            message: error.toString()
          };
        case 12:
          return {
            status: 409,
            message: error.toString()
          };
        default:
          return {
            status: 500,
            message: result || error
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
      var couchbase_callback, def, query, _error, _success;
      def = Q.defer();

      /*
       * Send the success response
       * @private
       */
      _success = function(response) {
        if (options.success != null) {
          options.success(response);
        }
        return def.resolve(response);
      };

      /*
       * Send the error response
       * @private
       */
      _error = function(err) {
        if ((options != null) && (options.error != null)) {
          options.error(_couchbaseErrorFormat(err));
        }
        return def.reject(_couchbaseErrorFormat(err));
      };

      /*
       * Callback to get the updated datas
       * @private
       */
      couchbase_callback = function(err, result) {
        var id, item, response, _i, _len;
        if (options.trace) {
          console.log("  - method:");
          console.log(method);
          console.log("  - id:");
          switch (typeof model.url) {
            case "function":
              console.log(_keyFormat(model.url()));
              break;
            case "string":
              console.log(model.url);
          }
          console.log(options);
          console.log("  - result:");
          console.log(result);
        }
        if ((err != null) && (err !== 0 || (err.length != null) && err.length > 0)) {
          if (options.ids == null) {
            _error(err);
          } else {
            _error(err, result);
          }
          if (options.trace) {
            console.log("  - err:");
            console.log(err);
          }
          return;
        }
        if (_.isArray(result)) {
          if ((options != null) && options.reduce) {
            response = result[0] != null ? result[0].value : 0;
          } else {
            response = [];
            for (_i = 0, _len = result.length; _i < _len; _i++) {
              item = result[_i];
              response.push(item.value);
            }
          }
        } else if (options.ids != null) {
          response = [];
          for (id in result) {
            item = result[id];
            response.push(item.value);
          }
        } else {
          response = result.value;
        }
        if (options.join === true && (model.join != null)) {
          model.join(response, function(err, joinedDatas) {
            if (err != null) {
              return _error(err);
            } else {
              return _success(joinedDatas);
            }
          });
          return;
        } else if (typeof options.join === "function") {
          options.join(model, response, function(err, joinedDatas) {
            if (err != null) {
              return _error(err);
            } else {
              return _success(joinedDatas);
            }
          });
          return;
        }
        _success(response);
        if (options.trace) {
          console.log("  - response:");
          console.log(response);
          return console.log("-----");
        }
      };
      if (options.trace) {
        console.log("-----");
        console.log("Backbone Couchbase:");
        console.log(" - method:");
        console.log(method);
      }
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
          if (options.ids != null) {
            if (typeof options.ids === "string") {
              options.ids = [options.ids];
            }
            if (!_.isArray(options.ids)) {
              _error(new Error("options.ids must be a String or an Array!"));
            } else {
              bucket.getMulti(_keysFormat(model.url, options.ids), couchbase_callback);
            }
          } else {
            query = ViewQuery.from(model.designDocument || model.url, options.viewName || model.defaultView);
            if (options.custom != null) {
              query.custom(options.custom);
            }
            query.reduce(options.reduce || false);
            if (options.stale != null) {
              query.stale(options.stale);
            }
            bucket.query(query, couchbase_callback);
          }
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
