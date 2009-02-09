require 'git_support'

class TC_Object < Test::Unit::TestCase
  include GitSupport

  def test_find
    assert_instance_of Wiki::Tree, Wiki::Object.find(@repo, '')
    assert_instance_of Wiki::Tree, Wiki::Tree.find(@repo, '')
    assert_nil Wiki::Page.find(@repo, '')

    assert_instance_of Wiki::Tree, Wiki::Object.find(@repo, '/')
    assert_instance_of Wiki::Tree, Wiki::Tree.find(@repo, '/')
    assert_nil Wiki::Page.find(@repo, '/')

    assert_instance_of Wiki::Page, Wiki::Object.find(@repo, 'init.txt')
    assert_nil Wiki::Tree.find(@repo, 'init.txt')
    assert_instance_of Wiki::Page, Wiki::Page.find(@repo, 'init.txt')

    assert_instance_of Wiki::Tree, Wiki::Object.find(@repo, '/')
    assert_instance_of Wiki::Tree, Wiki::Tree.find(@repo, '/')
    assert_nil Wiki::Page.find(@repo, '/')

    assert_instance_of Wiki::Tree, Wiki::Object.find(@repo, '/root')
    assert_instance_of Wiki::Tree, Wiki::Tree.find(@repo, '/root')
    assert_nil Wiki::Page.find(@repo, '/root')
  end

  def test_find!
    assert_instance_of Wiki::Tree, Wiki::Object.find!(@repo, '/root')
    assert_instance_of Wiki::Tree, Wiki::Tree.find!(@repo, '/root')
    assert_raise Wiki::Object::NotFound do
      Wiki::Page.find!(@repo, '/root')
    end

    assert_instance_of Wiki::Page, Wiki::Object.find!(@repo, '/init.txt')
    assert_instance_of Wiki::Page, Wiki::Page.find!(@repo, '/init.txt')
    assert_raise Wiki::Object::NotFound do
      Wiki::Tree.find!(@repo, '/init.txt')
    end

    assert_raise Wiki::Object::NotFound do
      Wiki::Object.find!(@repo, '/foo')
    end
    assert_raise Wiki::Object::NotFound do
      Wiki::Page.find!(@repo, '/foo')
    end
    assert_raise Wiki::Object::NotFound do
      Wiki::Tree.find!(@repo, '/foo')
    end
  end

  def test_new?
    assert !Wiki::Page.find(@repo, 'init.txt').new?
    assert !Wiki::Tree.find(@repo, '').new?
    assert Wiki::Page.new(@repo, 'new').new?
    assert Wiki::Tree.new(@repo, 'new').new?
  end

  def test_type
    assert Wiki::Page.find(@repo, 'init.txt').page?
    assert Wiki::Tree.find(@repo, '').tree?
  end

  def test_name
    assert_equal 'name.ext', Wiki::Object.new(@repo, '/path/name.ext').name
  end

  def test_pretty_name
    assert_equal 'name', Wiki::Object.new(@repo, '/path/name.ext').pretty_name
  end

  def test_path
    assert_equal 'path/name.ext', Wiki::Object.new(@repo, '/path/name.ext').path
  end

  def test_safe_name
    assert_equal '._____-_0123456789abc', Wiki::Object.new(@repo, '.#+*?=-_0123456789abc').safe_name
  end
end