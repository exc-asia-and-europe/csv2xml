# VRA Core 4 XML Transform Tool
The VRA Core 4 XML Transform Tool (**csv2xml**) converts descriptive work and image metadata from flat tables (.csv) to structured VRA Core 4 XML. It makes use of a template with predefined headers. Users may work with the tool in a simple or advanced mode. The transform tool performs XML validation and provides feedback in case of errors. it can also transform VRA Core 4 XMLinto RDF/XML using the VRA Ontology. 

The tool is an App for eXist-db database version 3. While the transformation of VRA Core 4 XML is the current use case, it can be used for any type of transformation from csv to xml. 

User manual, templates, and sample data can be found in the doc section.

## Technical information
**csv2xml** is designed as an app for the "open source native XML database" [eXist-db](http://www.exist-db.org). To build the app on your own, clone the Github-Repository and run

```
 ant
``` 

You can then install the generated .xar (build/csv2xml.xar) using the eXist Dashboard (see [http://exist-db.org/exist/apps/doc/dashboard.xml#D2.2.4](http://exist-db.org/exist/apps/doc/dashboard.xml#D2.2.4)).

##Templating/Mapping

**csv2xml** is capable to generate not only VRA XML files but also files of any xml schema by using mappings/templates

###mappings.xml

[mappings/mappings.xml](mappings/mappings.xml) keeps a list, describing the existing mappings and pointing to the subcollection which contains the parsing definitions and the templates:

    <mapping active="true" selected="false"> <!-- set @active="false" to hide it in the selection dropdown -->
        <collection>example</collection>  <!-- the subcollection containing the mapping -->
        <name>example mapping</name> <!-- mapping name which gets displayed in the selection dropdown -->
        <descripton>example mapping for new features etc</descripton> <!-- mapping description -->
    </mapping>

###$mapping-collection/csv-map.xml and $mapping-collection/templates/$template-file.xml

In [mappings/example/csv-map.xml](mappings/example/csv-map.xml) the csv columns get mapped to a key 

    <mapping key="IMAGE_Filename">$line/column[@heading-index="IMAGE_Filename"]/string()</mapping>

which has his correnspondency in the template file, (i.e.  [mappings/example/templates/vra-image-template.xml](mappings/example/templates/vra-image-template.xml))

    <image xmlns="http://www.vraweb.org/vracore4.htm" id="$IMAGE_ID$" href="$IMAGE_Filename$">

framed in $ chars. The mapping node's value is an xquery which gets evaluated by the eXist processor ( [util:eval()](http://exist-db.org/exist/apps/doc/util.xml) ). To access a row-value in the CSV line ($line), you can use three different "adresses":

- the heading name, if you got an csv with column headings in the first row

        $line/column[@heading-index="IMAGE_Filename"]/string()

- the numeric index of the row starting at 1

        $line/column[@num-index="17"]/string()

- a char index according to excel's schema (A=1, B=2 .... AA=27 ...)

        $line/column[@char-index="Q"]/string()

The template is parsed to a string and then the framed keys get replaced by the result of the xquery eval.

###$mapping-collection/_mapping-settings.xml

In [mappings/example/_mapping-settings.xml](mappings/example/_mapping-settings.xml) the main settings and definitions are done. Some of these settings are self explaining, some need some explanation:

    <importNamespaces>
        <ns prefix="">http://www.vraweb.org/vracore4.htm</ns>
        <ns prefix="svg">https://www.w3.org/2000/svg</ns>
    </importNamespaces>

Namespaces which are used in the evaluated xquery code. These get imported in each evaluation.

    <uniqueValues>
        <value>//work/@id/string()</value>
        <value>//image/@id/string()</value>
    </uniqueValues>

XPath to values which have to be unique (like IDs). If a processed template gets an already existing value, the template gets abandoned and will not get inserted in the final XML.

    <templates uses-headings="true"> <!-- CSV has a heading row. Starting line wil get set to 2 in the frontend -->
        <parent>parent-template.xml</parent>
        <template>
            <key>vraWork</key>
            <filename>vra-work-template.xml</filename>
            <targetNode>vra//csv2xml:vra-templates</targetNode>
        </template>
        <template>
            <key>vraImage</key>
            <filename>vra-image-template.xml</filename>
            <targetNode>vra//csv2xml:vra-templates</targetNode>
        </template>
    </templates>

Here the template files are defined. For each line there has to be a [parent template](mappings/example/templates/parent-template.xml) which may contain some wrapping nodes for this line. The processed templates get inserted _before_ the node pointed to by &lt;targetNode\&gt;. You can use the internal namespace _csv2xml_ for anchor nodes like this:

    <csv2xml:vra-templates xmlns:csv2xml="http://hra.uni-hd.de/csv2xml/template"/>

 These anchors get removed after all processing is done.

    <transformations>
        <transform label="unmodified VRA" name="plainVRA" active="true" selected="false" type="xsl">
            <importNamespaces>
                <ns prefix="">http://www.vraweb.org/vracore4.htm</ns>
            </importNamespaces>
            <paginationQuery>$generated-xml/vra/*[self::work or self::image]</paginationQuery>
            <xsl/>
            <validation-catalogs>
                <uri active="true">http://www.loc.gov/standards/vracore/vra.xsd</uri>
                <uri active="false">http://www.loc.gov/standards/vracore/vra-strict.xsd</uri>
            </validation-catalogs>
        </transform>
        <transform label="transform into RDF" name="rdf" active="true" selected="true" type="xsl">
            <importNamespaces>
                <ns prefix="">http://www.vraweb.org/vracore4.htm</ns>
                <ns prefix="vra">http://purl.org/vra/</ns>
                <ns prefix="rdf">http://www.w3.org/1999/02/22-rdf-syntax-ns#</ns>
            </importNamespaces>
            <paginationQuery>$generated-xml/*/*:Description</paginationQuery>
            <xsl>
                <uri active="true" selected="true">xsl/vra2rdf.xsl</uri>
            </xsl>
            <validation-catalogs/>
        </transform>
    </transformations>

Here the XSLTransformations are defined. Each &lt;transform/&gt; node defines a single transformation. The transformations are done step by step. If @selected="true" they are processed by default but can get deactivated in the advanced mode in the frontend. If there are namespaces used in the xsl files, declare them in the &lt;importNamespaces/&gt; section. 

&lt;validation-catalogs/&gt; contains uris pointing to xsd schemas against which the resulting xml gets validated. 
Validation is done by the Xerces2 library using the [eXist db internal validation functions](http://exist-db.org/exist/apps/doc/validation.xml#D2.2.4.4).

For the preview in the frontend there is the &lt;paginationQuery/&gt;. Use a xpath here which gets util:eval()'ed after the whole processing (including xsl-transformations). Each item in the result is treated as a page.
