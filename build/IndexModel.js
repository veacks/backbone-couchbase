
/*
 * @class IndexModel
 * @description Help to manage dee equality for indexes
 */

(function() {
  var IndexModel;

  module.exports = IndexModel = (function() {

    /*
     * @member {string} name - name of the index
     */
    IndexModel.prototype.name = String;


    /*
     * @member {boolean}  is_primary - is a primary index
     */

    IndexModel.prototype.is_primary = Boolean;


    /*
     * @member {string} using - Type of indexing (GSI or VIEW)
     */

    IndexModel.prototype.using = String;


    /*
     * @member {array} index_key - Keys to index
     */

    IndexModel.prototype.index_key = Array;


    /*
     * @constructor
     * @param {string} name - name of the index
     * @param {boolean}  is_primary - is a primary index
     * @param {string} using - Type of indexing (GSI or VIEW)
     * @param {array} index_key - Keys to index
     */

    function IndexModel(name, is_primary, using, index_key) {
      this.name = name;
      this.is_primary = is_primary || true;
      this.using = using || "GSI";
      this.index_key = index_key || [];
    }

    return IndexModel;

  })();

}).call(this);
