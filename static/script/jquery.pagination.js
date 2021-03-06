// Pagination links
// $('.pagination a').pagination('#page_element');
// $('#page_element').bind('pageLoaded', function() {});
// Written by Daniel Mendler
(function($) {
    $.fn.pagination = function(page) {
        var page = $(page);
	this.live('click', function() {
            $(this).addClass('loading');
            var href = this.href;
            page.load(href, function() {
                page.trigger('pageLoaded', [href]);
            });
            return false;
        });
    };
})(jQuery);
