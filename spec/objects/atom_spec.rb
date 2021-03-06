describe :atom do
  
  it "cannot initialize without element" do
    -> {Atom.new}.must_raise NotImplementedError
  end
  
  it "should be instance of it's elements type" do
    
    element = Element.create!(fixture(:elements,:user))
    user = User.create!(fixture(:atoms,:user))
    user.element.must_equal element
    
  end
  
  it "should be created by element" do
    
    element = Element.create!(fixture(:elements,:user))
    user = element.atoms.create!(fixture(:atoms,:user))
    user.element.must_equal element
    
  end
  
  it "serializes to csv" do
    element = Element.create!(fixture(:elements,:user))
    user = element.atoms.create!(fixture(:atoms,:user))
    user.to_csv.must_equal "user@test.com,name,surname\n"
  end
  
  
end