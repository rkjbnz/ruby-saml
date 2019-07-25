require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))

class ResponseTest < Test::Unit::TestCase

  context "Response" do
    should "raise an exception when response is initialized with nil" do
      assert_raises(ArgumentError) { OneLogin::RubySaml::Response.new(nil) }
    end

    should "be able to parse a document which contains ampersands" do
      XMLSecurity::SignedDocument.any_instance.stubs(:digests_match?).returns(true)
      OneLogin::RubySaml::Response.any_instance.stubs(:validate_conditions).returns(true)

      response = OneLogin::RubySaml::Response.new(ampersands_response)
      settings = OneLogin::RubySaml::Settings.new
      settings.idp_cert_fingerprint = 'c51985d947f1be57082025050846eb27f6cab783'
      response.settings = settings
      response.validate!
    end

    should "adapt namespace" do
      response = OneLogin::RubySaml::Response.new(response_document)
      assert !response.name_id.nil?
      response = OneLogin::RubySaml::Response.new(response_document_2)
      assert !response.name_id.nil?
      response = OneLogin::RubySaml::Response.new(response_document_3)
      assert !response.name_id.nil?
    end

    should "default to raw input when a response is not Base64 encoded" do
      decoded  = Base64.decode64(response_document_2)
      response = OneLogin::RubySaml::Response.new(decoded)
      assert response.document
    end

    context "Assertion" do
      should "only retreive an assertion with an ID that matches the signature's reference URI" do
        response = OneLogin::RubySaml::Response.new(wrapped_response_2)
        response.stubs(:conditions).returns(nil)
        settings = OneLogin::RubySaml::Settings.new
        settings.idp_cert_fingerprint = signature_fingerprint_1
        response.settings = settings
        assert response.name_id.nil?
      end
    end

    context "#validate!" do
      should "raise when encountering a condition that prevents the document from being valid" do
        response = OneLogin::RubySaml::Response.new(response_document)
        assert_raise(OneLogin::RubySaml::ValidationError) do
          response.validate!
        end
      end
    end

    context "#is_valid?" do
      should "return false when response is initialized with blank data" do
        response = OneLogin::RubySaml::Response.new('')
        assert !response.is_valid?
      end

      should "return false if settings have not been set" do
        response = OneLogin::RubySaml::Response.new(response_document)
        assert !response.is_valid?
      end

      should "return true when the response is initialized with valid data" do
        response = OneLogin::RubySaml::Response.new(response_document_4)
        response.stubs(:conditions).returns(nil)
        assert !response.is_valid?
        settings = OneLogin::RubySaml::Settings.new
        assert !response.is_valid?
        response.settings = settings
        assert !response.is_valid?
        settings.idp_cert_fingerprint = signature_fingerprint_1
        assert response.is_valid?
      end

      should "should be idempotent when the response is initialized with invalid data" do
        response = OneLogin::RubySaml::Response.new(response_document_4)
        response.stubs(:conditions).returns(nil)
        settings = OneLogin::RubySaml::Settings.new
        response.settings = settings
        assert !response.is_valid?
        assert !response.is_valid?
      end

      should "should be idempotent when the response is initialized with valid data" do
        response = OneLogin::RubySaml::Response.new(response_document_4)
        response.stubs(:conditions).returns(nil)
        settings = OneLogin::RubySaml::Settings.new
        response.settings = settings
        settings.idp_cert_fingerprint = signature_fingerprint_1
        assert response.is_valid?
        assert response.is_valid?
      end

      should "return true when using certificate instead of fingerprint" do
        response = OneLogin::RubySaml::Response.new(response_document_4)
        response.stubs(:conditions).returns(nil)
        settings = OneLogin::RubySaml::Settings.new
        response.settings = settings
        settings.idp_cert = signature_1
        assert response.is_valid?
      end

      should "not allow signature wrapping attack" do
        response = OneLogin::RubySaml::Response.new(response_document_4)
        response.stubs(:conditions).returns(nil)
        settings = OneLogin::RubySaml::Settings.new
        settings.idp_cert_fingerprint = signature_fingerprint_1
        response.settings = settings
        assert response.is_valid?
        assert response.name_id == "test@onelogin.com"
      end

      should "support dynamic namespace resolution on signature elements" do
        response = OneLogin::RubySaml::Response.new(fixture("no_signature_ns.xml"))
        response.stubs(:conditions).returns(nil)
        settings = OneLogin::RubySaml::Settings.new
        response.settings = settings
        settings.idp_cert_fingerprint = "28:74:9B:E8:1F:E8:10:9C:A8:7C:A9:C3:E3:C5:01:6C:92:1C:B4:BA"
        XMLSecurity::SignedDocument.any_instance.expects(:validate_signature).returns(true)
        assert response.validate!
      end

      should "validate ADFS assertions" do
        response = OneLogin::RubySaml::Response.new(fixture(:adfs_response_sha256))
        response.stubs(:conditions).returns(nil)
        settings = OneLogin::RubySaml::Settings.new
        settings.idp_cert_fingerprint = "28:74:9B:E8:1F:E8:10:9C:A8:7C:A9:C3:E3:C5:01:6C:92:1C:B4:BA"
        response.settings = settings
        assert response.validate!
      end

      should "validate the digest" do
        response = OneLogin::RubySaml::Response.new(r1_response_document_6)
        response.stubs(:conditions).returns(nil)
        settings = OneLogin::RubySaml::Settings.new
        settings.idp_cert = Base64.decode64(r1_signature_2)
        response.settings = settings
        assert response.validate!
      end

      should "validate SAML 2.0 XML structure" do
        resp_xml = Base64.decode64(response_document_4).gsub(/emailAddress/,'test')
        response = OneLogin::RubySaml::Response.new(Base64.encode64(resp_xml))
        response.stubs(:conditions).returns(nil)
        settings = OneLogin::RubySaml::Settings.new
        settings.idp_cert_fingerprint = signature_fingerprint_1
        response.settings = settings
        assert_raises(OneLogin::RubySaml::ValidationError, 'Digest mismatch'){ response.validate! }
      end

      should "Prevent node text with comment (VU#475445) attack" do
        response_doc = File.read(File.join(File.dirname(__FILE__), "responses", 'response_node_text_attack.xml.base64'))
        response = OneLogin::RubySaml::Response.new(response_doc)

        assert_equal "support@onelogin.com", response.name_id
        assert_equal "smith", response.attributes["surname"]
      end

      context '#validate_audience' do
        should "return true when sp_entity_id not set or empty" do
          response = OneLogin::RubySaml::Response.new(response_document_4)
          response.stubs(:conditions).returns(nil)
          settings = OneLogin::RubySaml::Settings.new
          response.settings = settings
          settings.idp_cert_fingerprint = signature_fingerprint_1
          assert response.is_valid?
          settings.sp_entity_id = ''
          assert response.is_valid?
        end

        should "return false when sp_entity_id set to incorrectly" do
          response = OneLogin::RubySaml::Response.new(response_document_4)
          response.stubs(:conditions).returns(nil)
          settings = OneLogin::RubySaml::Settings.new
          response.settings = settings
          settings.idp_cert_fingerprint = signature_fingerprint_1
          settings.sp_entity_id = 'wrong_audience'
          assert !response.is_valid?
        end

        should "return true when sp_entity_id set to correctly" do
          response = OneLogin::RubySaml::Response.new(response_document_4)
          response.stubs(:conditions).returns(nil)
          settings = OneLogin::RubySaml::Settings.new
          response.settings = settings
          settings.idp_cert_fingerprint = signature_fingerprint_1
          settings.sp_entity_id = 'audience'
          assert response.is_valid?
        end
      end
    end

    context "#name_id" do
      should "extract the value of the name id element" do
        response = OneLogin::RubySaml::Response.new(response_document)
        assert_equal "support@onelogin.com", response.name_id

        response = OneLogin::RubySaml::Response.new(response_document_3)
        assert_equal "someone@example.com", response.name_id
      end

      should "be extractable from an OpenSAML response" do
        response = OneLogin::RubySaml::Response.new(fixture(:open_saml))
        assert_equal "someone@example.org", response.name_id
      end

      should "be extractable from a Simple SAML PHP response" do
        response = OneLogin::RubySaml::Response.new(fixture(:simple_saml_php))
        assert_equal "someone@example.com", response.name_id
      end
    end

    context "#check_conditions" do
      should "check time conditions" do
        response = OneLogin::RubySaml::Response.new(response_document)
        assert !response.send(:validate_conditions, true)
        response = OneLogin::RubySaml::Response.new(response_document_6)
        assert response.send(:validate_conditions, true)
        time     = Time.parse("2011-06-14T18:25:01.516Z")
        Time.stubs(:now).returns(time)
        response = OneLogin::RubySaml::Response.new(response_document_5)
        assert response.send(:validate_conditions, true)
      end

      should "optionally allow for clock drift" do
        # The NotBefore condition in the document is 2011-06-14T18:21:01.516Z
        Time.stubs(:now).returns(Time.parse("2011-06-14T18:21:01Z"))
        response = OneLogin::RubySaml::Response.new(response_document_5, :allowed_clock_drift => 0.515)
        assert !response.send(:validate_conditions, true)

        Time.stubs(:now).returns(Time.parse("2011-06-14T18:21:01Z"))
        response = OneLogin::RubySaml::Response.new(response_document_5, :allowed_clock_drift => 0.516)
        assert response.send(:validate_conditions, true)
      end
    end

    context "#attributes" do
      should "extract the first attribute in a hash accessed via its symbol" do
        response = OneLogin::RubySaml::Response.new(response_document)
        assert_equal "demo", response.attributes[:uid]
      end

      should "extract the first attribute in a hash accessed via its name" do
        response = OneLogin::RubySaml::Response.new(response_document)
        assert_equal "demo", response.attributes["uid"]
      end

      should "extract all attributes" do
        response = OneLogin::RubySaml::Response.new(response_document)
        assert_equal "demo", response.attributes[:uid]
        assert_equal "value", response.attributes[:another_value]
      end

      should "work for implicit namespaces" do
        response = OneLogin::RubySaml::Response.new(response_document_3)
        assert_equal "someone@example.com", response.attributes["http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"]
      end

      should "not raise on responses without attributes" do
        response = OneLogin::RubySaml::Response.new(response_document_4)
        assert_equal OneLogin::RubySaml::Attributes.new, response.attributes
      end

      should "extract attributes from all AttributeStatement tags" do
        assert_equal "smith", response_with_multiple_attribute_statements.attributes[:surname]
        assert_equal "bob", response_with_multiple_attribute_statements.attributes[:firstname]
      end

      should "be manipulable by hash methods such as #merge and not raise an exception" do
        response = OneLogin::RubySaml::Response.new(response_document)
        response.attributes.merge({ :testing_attribute => "test" })
      end

      should "be manipulable by hash methods such as #shift and not raise an exception" do
        response = OneLogin::RubySaml::Response.new(response_document)
        response.attributes.shift
      end

      should "be manipulable by hash methods such as #merge! and actually contain the value" do
        response = OneLogin::RubySaml::Response.new(response_document)
        response.attributes.merge!({ :testing_attribute => "test" })
        assert response.attributes[:testing_attribute]
      end

      should "be manipulable by hash methods such as #shift and actually remove the value" do
        response = OneLogin::RubySaml::Response.new(response_document)
        removed_value = response.attributes.shift
        assert_nil response.attributes[removed_value[0]]
      end
    end

    context "#session_expires_at" do
      should "extract the value of the SessionNotOnOrAfter attribute" do
        response = OneLogin::RubySaml::Response.new(response_document)
        assert response.session_expires_at.is_a?(Time)

        response = OneLogin::RubySaml::Response.new(response_document_2)
        assert response.session_expires_at.nil?
      end
    end

    context "#issuer" do
      should "return the issuer inside the response assertion" do
        response = OneLogin::RubySaml::Response.new(response_document)
        assert_equal "https://app.onelogin.com/saml/metadata/13590", response.issuer
      end

      should "return the issuer inside the response" do
        response = OneLogin::RubySaml::Response.new(response_document_2)
        assert_equal "wibble", response.issuer
      end
    end

    context "#success" do
      should "find a status code that says success" do
        response = OneLogin::RubySaml::Response.new(response_document)
        response.success?
      end
    end

    context '#xpath_first_from_signed_assertion' do
      should 'not allow arbitrary code execution' do
        malicious_response_document = fixture('response_eval', false)
        response = OneLogin::RubySaml::Response.new(malicious_response_document)
        response.send(:xpath_first_from_signed_assertion)
        assert_equal($evalled, nil)
      end
    end

    context "#multiple values" do
      should "extract single value as string" do
        assert_equal "demo", response_multiple_attr_values.attributes[:uid]
      end

      should "extract single value as string in compatibility mode off" do
        OneLogin::RubySaml::Attributes.single_value_compatibility = false
        assert_equal ["demo"], response_multiple_attr_values.attributes[:uid]
        # classes are not reloaded between tests so restore default
        OneLogin::RubySaml::Attributes.single_value_compatibility = true
      end

      should "extract first of multiple values as string for b/w compatibility" do
        assert_equal 'value1', response_multiple_attr_values.attributes[:another_value]
      end

      should "extract first of multiple values as string for b/w compatibility in compatibility mode off" do
        OneLogin::RubySaml::Attributes.single_value_compatibility = false
        assert_equal ['value1', 'value2'], response_multiple_attr_values.attributes[:another_value]
        OneLogin::RubySaml::Attributes.single_value_compatibility = true
      end

      should "return array with all attributes when asked in XML order" do
        assert_equal ['value1', 'value2'], response_multiple_attr_values.attributes.multi(:another_value)
      end

      should "return array with all attributes when asked in XML order in compatibility mode off" do
        OneLogin::RubySaml::Attributes.single_value_compatibility = false
        assert_equal ['value1', 'value2'], response_multiple_attr_values.attributes.multi(:another_value)
        OneLogin::RubySaml::Attributes.single_value_compatibility = true
      end

      should "return first of multiple values when multiple Attribute tags in XML" do
        assert_equal 'role1', response_multiple_attr_values.attributes[:role]
      end

      should "return first of multiple values when multiple Attribute tags in XML in compatibility mode off" do
        OneLogin::RubySaml::Attributes.single_value_compatibility = false
        assert_equal ['role1', 'role2', 'role3'], response_multiple_attr_values.attributes[:role]
        OneLogin::RubySaml::Attributes.single_value_compatibility = true
      end

      should "return all of multiple values in reverse order when multiple Attribute tags in XML" do
        assert_equal ['role1', 'role2', 'role3'], response_multiple_attr_values.attributes.multi(:role)
      end

      should "return all of multiple values in reverse order when multiple Attribute tags in XML in compatibility mode off" do
        OneLogin::RubySaml::Attributes.single_value_compatibility = false
        assert_equal ['role1', 'role2', 'role3'], response_multiple_attr_values.attributes.multi(:role)
        OneLogin::RubySaml::Attributes.single_value_compatibility = true
      end

      should "return all of multiple values when multiple Attribute tags in multiple AttributeStatement tags" do
        OneLogin::RubySaml::Attributes.single_value_compatibility = false
        assert_equal ['role1', 'role2', 'role3'], response_with_multiple_attribute_statements.attributes.multi(:role)
        OneLogin::RubySaml::Attributes.single_value_compatibility = true
      end

      should "return nil value correctly" do
        assert_nil response_multiple_attr_values.attributes[:attribute_with_nil_value]
      end

      should "return nil value correctly when not in compatibility mode off" do
        OneLogin::RubySaml::Attributes.single_value_compatibility = false
        assert_equal [nil], response_multiple_attr_values.attributes[:attribute_with_nil_value]
        OneLogin::RubySaml::Attributes.single_value_compatibility = true
      end

      should "return multiple values including nil and empty string" do
        response = OneLogin::RubySaml::Response.new(fixture(:response_with_multiple_attribute_values))
        assert_equal ["", "valuePresent", nil, nil], response.attributes.multi(:attribute_with_nils_and_empty_strings)
      end

      should "return multiple values from [] when not in compatibility mode off" do
        OneLogin::RubySaml::Attributes.single_value_compatibility = false
        assert_equal ["", "valuePresent", nil, nil], response_multiple_attr_values.attributes[:attribute_with_nils_and_empty_strings]
        OneLogin::RubySaml::Attributes.single_value_compatibility = true
      end

      should "check what happens when trying retrieve attribute that does not exists" do
        assert_equal nil, response_multiple_attr_values.attributes[:attribute_not_exists]
        assert_equal nil, response_multiple_attr_values.attributes.single(:attribute_not_exists)
        assert_equal nil, response_multiple_attr_values.attributes.multi(:attribute_not_exists)

        OneLogin::RubySaml::Attributes.single_value_compatibility = false
        assert_equal nil, response_multiple_attr_values.attributes[:attribute_not_exists]
        assert_equal nil, response_multiple_attr_values.attributes.single(:attribute_not_exists)
        assert_equal nil, response_multiple_attr_values.attributes.multi(:attribute_not_exists)
        OneLogin::RubySaml::Attributes.single_value_compatibility = true
      end
    end
  end
end
