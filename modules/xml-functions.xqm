xquery version "3.0";

module namespace xml-functions="http://hra.uni-heidelberg.de/ns/csv2vra/xml-functions";
import module namespace functx="http://www.functx.com";

declare namespace json="http://www.json.org";
declare namespace csv2xml="http://hra.uni-hd.de/csv2xml/template";

declare variable $xml-functions:mappings-path := "..";
declare variable $xml-functions:mapping-definitions := doc($xml-functions:mappings-path || "/mappings/mappings.xml");
declare variable $xml-functions:temp-dir := xs:anyURI("/db/tmp/");
declare variable $xml-functions:ERROR := xs:QName("xml-functions:error");

declare function xml-functions:get-catalogs($mapping, $transformation) {
    let $catalogs := doc("../mappings/" || $mapping || "/_mapping-settings.xml")//transformations/transform[@name=$transformation]/validation-catalogs/uri
    return 
        <root>
            {
                for $cat in $catalogs
                return
                    <catalogs json:array="true">
                        <uri>{$cat/string()}</uri>
                        <active>{$cat/@active/string()}</active>
                    </catalogs>
            }
        </root>
};

declare function xml-functions:get-transformations($mapping) {
    let $transformations := doc("../mappings/" || $mapping || "/_mapping-settings.xml")//transformations/transform
    return
        <root>
            {
                for $t in $transformations
                return
                    <transform json:array="true">
                        <name>{$t/@name/string()}</name>
                        <label>{$t/@label/string()}</label>
                        <active>{$t/@active/string()}</active>
                        <selected>{$t/@selected/string()}</selected>
                    </transform>
            }
        </root>    
};

declare function xml-functions:get-xsls($mapping, $transform-name) {
    let $transformations := doc("../mappings/" || $mapping || "/_mapping-settings.xml")//transformations/transform[@name=$transform-name]
(:    let $log := util:log("INFO", doc("../mappings/" || $mapping || "/_mapping-settings.xml")//transformations):)
    return 
        <root>
            {
                for $xsl in $transformations/xsl/uri
                return
                    <xsl json:array="true">
                        <uri>{$xsl/string()}</uri>
                        <active>{$xsl/@active/string()}</active>
                        <selected>{$xsl/@selected/string()}</selected>
                    </xsl>
            }
        </root>
};

declare %private function xml-functions:_transform($transformations-sequence, $xml) {
    let $xsl := $transformations-sequence[1]
    let $mapping-name := session:get-attribute("mapping-name")
(:    let $log := util:log("INFO", "../mappings/" || $mapping-name || "/" || $xsl):)
    let $xsl-doc := doc("../mappings/" || $mapping-name || "/" || $xsl)
    let $xml := transform:transform($xml, $xsl-doc, ())
    return
        if(count($transformations-sequence) > 1) then
            xml-functions:_transform(fn:subsequence($transformations-sequence, 2), $xml)
        else
            $xml
};

declare function xml-functions:apply-xsls($xsls as xs:string*){
(:    let $log := util:log("INFO", "xsls: " || $xsls):)
    let $file-uri := session:get-attribute("file-uri")

    let $transformed-file-uri := functx:substring-before-last($file-uri, ".xml") || "_transformed.xml"
    let $mapping-name := session:get-attribute("mapping-name")
    return 
(:        try {:)
            let $xml := doc($file-uri)
            let $xml :=
                if(count($xsls) > 0) then
                    xml-functions:_transform($xsls, $xml)
                else
                    $xml
            let $stored-xml-uri := xmldb:store($xml-functions:temp-dir, $transformed-file-uri, $xml)
            return 
                $stored-xml-uri
(:        } catch * {:)
(:            error($xml-functions:ERROR, "XSL-Transforming failed. " || $err:code || " " || $err:description || " " || $err:value):)
(:        }:)
};

declare function xml-functions:apply-mapping($mapping-definition as node(), $line as node()) {
    let $clear-default-ns := util:declare-namespace("", xs:anyURI(""))
    let $replace-map := 
        map:new(
            for $mapping in $mapping-definition//mapping
                let $key := $mapping/@key/string()
                let $queryString := $mapping/string()
        
                let $changeFrom := "\$" || $key || "\$"
                let $changeTo := util:eval($queryString)
                return
                    map:entry($changeFrom, $changeTo)
        )
    return
        session:set-attribute("mapped-values", $replace-map)

};

declare function xml-functions:replace-template-variables($template-string as xs:string) as xs:string {
    let $replace-map := session:get-attribute("mapped-values")

    let $from-seq := map:keys($replace-map)
    let $to-seq :=
        for $from in $from-seq
            let $to-value := 
                if ($replace-map($from)) then
                    xs:string($replace-map($from))
                else
                    xs:string("")
            return
                $to-value
    
    let $return :=
        functx:replace-multi($template-string, $from-seq, $to-seq)

    (: remove unreplaced vars and dollar sign:)
    let $return :=
        functx:replace-multi($return, ("\$.*?\$", "\|\|\|dollar\|\|\|", "\|\|\|quot\|\|\|"), ("", "\&#36;", "&amp;quot;"))
            
    return 
        $return
};

declare function xml-functions:remove-empty-attributes($element as element()) as element() {
    element { node-name($element)}
    {
        $element/@*[string-length(.) ne 0],
        for $child in $element/node( )
            return 
                if ($child instance of element()) then
                    xml-functions:remove-empty-attributes($child)
                else
                    $child
    }
};

declare function xml-functions:remove-empty-elements($nodes as node()*)  as node()* {
   for $node in $nodes
   return
    if ($node instance of element()) then
        if (normalize-space($node) = '') then 
            ()
        else element { node-name($node) }
            { 
                $node/@*,
                xml-functions:remove-empty-elements($node/node())
            }
    else 
        if ($node instance of document-node()) then
            xml-functions:remove-empty-elements($node/node())
        else 
            $node
};

declare function xml-functions:store-parent($parent as node()*) as xs:string{
    let $session-saved-uri := session:get-attribute("file-uri")
    let $res-name := 
        if (empty($session-saved-uri)) then
            util:uuid() || ".xml"
        else
            functx:substring-after-last($session-saved-uri, "/")
    
    let $session-set := session:set-attribute("file-uri", $xml-functions:temp-dir || "/" || $res-name)
    return 
        try {
            (: if there is already a xnml file for this session, overwrite it:)
            let $store := xmldb:store($xml-functions:temp-dir, $res-name, $parent)
            return
                $res-name
        } catch * {
            error($xml-functions:ERROR, "creating temp file failed", $xml-functions:temp-dir || "/" || $res-name || ":" || $err:code || " " || $err:description || " " || $err:value)
        }
};

declare function xml-functions:store-node($node-as-string as xs:string, $target-node-query){
    let $mapping-name := session:get-attribute("mapping-name")
    (: open temp file :)
    let $document-uri := session:get-attribute("file-uri")
    let $generated-doc := doc($document-uri)
    let $col := functx:substring-before-last($document-uri, "/")
    let $res := functx:substring-after-last($document-uri, "/")
    let $xml := parse-xml($node-as-string)
    let $xml := xml-functions:remove-empty-attributes($xml/*)

    let $importNamespaces := xml-functions:importNamespaces()
    let $target-node := util:eval("$generated-doc//" || $target-node-query)

    (: check for already existing unique values (i.e. id's) :)
    let $unique-values := session:get-attribute("uniqueValues")
    let $unique-test := 
        for $value in $unique-values//value
            let $this-value := util:eval("root($xml)" || $value/string())
            let $value-exists := 
                if(count(util:eval("$generated-doc" || $value/string() || "[. = $this-value]")) > 0) then
                    true()
                else
                    false()
            return
                $value-exists
                
    return
        (: if there is one of the unique values found, do not insert the generated xml  :)
        if($unique-test = true()) then 
            true()
        else
            try {
                update insert $xml preceding $target-node 
            } catch * {
                error($xml-functions:ERROR, "Error inserting the processed template. " || $err:code || " " || $err:description || " " || $err:value)
            }


(:        util:log("INFO", $generated-doc):)
};


declare function xml-functions:load-templates-in-session() {
    let $mapping-name := session:get-attribute("mapping-name")
    let $settings-uri :=  $xml-functions:mappings-path || "/mappings/" || $mapping-name || "/_mapping-settings.xml"

    (: get the template-filenames:)
    let $settings := doc($settings-uri)
    (: store unique value queries in session  :)
    let $store-session := session:set-attribute("uniqueValues", $settings//uniqueValues)
    
    let $templates := $settings/settings/templates/template

    (: serialize each template :)
    let $templates-strings := 
        map:new(
            for $template in $templates
                let $target-node-query := $template/targetNode/string()
                let $template-filename := $template/filename/string()

                (: load the XML templates :)
                let $xml-uri := $xml-functions:mappings-path || "/mappings/" || $mapping-name || "/templates/" || $template-filename
(:                let $log := util:log("INFO", "tfn:" || $xml-uri):)
                let $xml := doc($xml-uri)
                let $xml-string := serialize($xml)
(:                let $log := util:log("INFO", $xml-string):)
                return 
                    map:entry($template-filename, 
                        map{
                                "string": $xml-string,
                                "targetNodeQuery": $target-node-query
                        }
                    )
        )
    let $store-session := session:set-attribute("template-strings", $templates-strings)
    return
        $templates-strings
};

declare function xml-functions:importNamespaces() {
    let $presetDefinition := session:get-attribute("selectedPresetDefiniton")
    let $namespace-declarations := $presetDefinition/importNamespaces
    return
        for $namespace in $namespace-declarations//ns 
            let $prefix := $namespace/@prefix/string()
            let $namespace-uri := xs:anyURI($namespace/string())
(:            let $log := util:log("INFO", "declaring namespace " || $prefix || ":" || $namespace-uri):)
            return
                try {
                    util:declare-namespace($prefix, $namespace-uri)
                } catch * {
(:                    util:log("INFO", $err),:)
                    error($xml-functions:ERROR, "Error declaring namespace " || $prefix || ":" || $namespace-uri)
                }
};

declare function xml-functions:get-mapping-settings() {
    let $mapping-name := session:get-attribute("mapping-name")
    return
        if (not(session:get-attribute("mapping-settings"))) then
            let $settings-uri :=  $xml-functions:mappings-path || "/mappings/" || $mapping-name || "/_mapping-settings.xml"
            let $settings := doc($settings-uri)
            let $session-store := session:set-attribute("mapping-settings", $settings)
            return 
                $settings
        else
            session:get-attribute("mapping-settings")
};

declare function xml-functions:count-pagination-items() as xs:integer {
    let $import-namespaces := xml-functions:importNamespaces()
    let $presetDefinition := session:get-attribute("selectedPresetDefiniton")
    let $pagination-query := $presetDefinition/paginationQuery/string()
    let $log := util:log("DEBUG", "paginationQuery" || $pagination-query)
    
    let $generated-xml := doc(session:get-attribute("transformed-filename"))
    return
        util:eval("count(" || $pagination-query || ")")

};

declare function xml-functions:get-pagination-item($page as xs:integer) {
    let $mapping-name := session:get-attribute("mapping-name")
    let $presetDefinition := session:get-attribute("selectedPresetDefiniton")
    let $pagination-query := $presetDefinition/paginationQuery/string()
    
    
    let $generated-xml := doc(session:get-attribute("transformed-filename"))
    let $importNamespaces := xml-functions:importNamespaces()
    let $page-item := util:eval($pagination-query || "[" || $page || "]")
    return
        $page-item
};

declare function xml-functions:cleanupXML(){
    let $generated-doc := doc(session:get-attribute("transformed-filename"))
(:    let $log := util:log("INFO", session:get-attribute("file-uri")):)
    (:  removeCSV2XMLnodes  :)
    for $node in root($generated-doc)//csv2xml:*
    return
        update delete $node
};