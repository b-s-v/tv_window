var req = '1';
var getAllterm = true;
var delSet = true;
var __admin__ = true;

function timer() {
    this.d       = document.getElementById('counter');
    this.started = false;
    this.val     = -1;
    this.count   = function() {
       if (this.started) {
          this.val++;
          this.d.innerHTML = this.val;
          setTimeout('mytimer.count()', 1000);
       }
    }
    this.start   = function() {
       this.started = true;
       this.count();
    }
    this.stop    = function() {
       this.started = false;
    }
}
var mytimer;
var req;
var last_mod = 0;

function loadXMLDoc(url) {
    if (window.XMLHttpRequest) {
        req = new XMLHttpRequest();
        req.onreadystatechange = processReqChange;
        req.open("GET", url, true);
        req.send(null);
    } else if (window.ActiveXObject) {
        req = new ActiveXObject("Microsoft.XMLHTTP");
        if (req) {
            req.onreadystatechange = processReqChange;
            req.open("GET", url, true);
            req.send();
        }
    }

}

function getStats() {
    if (__admin__ == true)
        loadXMLDoc('/cgi-bin/people_request.pl?nocahe='+Math.random()+'&lmod='+last_mod+'&f='+Math.random());
    setTimeout('getStats()', 5000);
}


function processReqChange() {
    if (req && req.readyState == 4) {
        if (req.status == 200) {
            var rdoc = req.responseXML.documentElement;
            if (rdoc && rdoc.nodeName == 'traff') {
                var total    = rdoc.getAttribute('total');
                var se_summs = rdoc.getElementsByTagName('se')[0].childNodes;
                for (var i = 0; i< se_summs.length; i++) {
                    var ctag  = se_summs[i];
                    var cnum  = ctag.firstChild.data;
                    var cline = document.getElementById(ctag.nodeName+'_stats');
                    var gline = document.getElementById(ctag.nodeName+'_graph');
                    var percent = Math.round((cnum / total) * 100);
                    if(cnum >= 10000) {
                       str = cnum + "";
                       l_str = str.substr(-3);
                       f_str = str.substring(0, str.length - l_str.length);
                       cline.innerHTML = f_str + "&#160;" + l_str;
                    } else {
                       cline.innerHTML = cnum;
                    }
                    gline.style.width = percent + '%';
                    cline.style.left  = percent + '%';
                }
                last_mod = rdoc.getAttribute('lmod');
                var termset = req.responseXML.documentElement.getElementsByTagName('t');

                for (var i = 0; i<termset.length; i++) {
                    var cterm  = termset[i];
                    appendTerm(cterm.getAttribute('s'), cterm.firstChild.data, termset.length);
                }
                getAllterm = false;
                delSet = true;
            }
        }
    }
}

function appendTerm(se, term, count_terms) {
    var block = document.getElementById('block');

    var line       = block.appendChild(document.createElement('li'));
    var ico        = line.appendChild(document.createElement('div'));
    var line_text  = line.appendChild(document.createElement('div'));
    var line_text2 = line.appendChild(document.createElement('div'));

    line.className       = 'reqLine';
    ico.className        = 'ico_' + se;
    line_text.className  = 'reqText';
    line_text2.className = 'reqEmpty';


    line_text.innerHTML  = '&#160;';
    line_text2.innerHTML = term;

    if(!getAllterm && delSet) {
       if($("#block > li").length > 14) {
          $("#block > li").slice(0,count_terms).slideUp(600, function() { $("#block > li:first-child").remove(); } );
          delSet = false;
       }
    }

}


$(document).ready(function(){
   getStats();
})
