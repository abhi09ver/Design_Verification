# UVM register

*Chapter: Register model (RAL) · source: attached*

Hi, my name is Cristian Slav and in this tutorial we are going to talk about the UVM register.
From the UVM documentation we get the definition of a register.
A register represents a set of fields that are accessible as a single entity.
And in our case for the Aligner, we have four registers.
Control, Status, Interrupt Requests Enable, and Interrupt Requests.
And these four registers we are going to model using the UVM register.
The way we model a register using the UVM register class is by creating a child class of uvm_reg.
And as we saw from the collaboration diagram, we can put in this child class as many instances of a reg field as we need.
The "UVM User Guide" provides quite a significant number of rules when it comes to the way we are coding an UVM register.
And let's go through the most important rules that we need to consider in our next tutorial in which we will code these registers in our environment.
The first rule is this one: The register type must contain a public class property for each field it contains.
This rule is extracted from the "UVM User Guide" and it means that in each register class that we are going to define, all the fields that we need to declare must be public.
The second rule is this one: The name of the field class property shall be the name of the field.
This is an easy rule to understand.
It means that all the register field instances that we will define under our register classes must have the same name as the name of the fields defined in the Aligner documentation.
The third rule says that the field class property shall have the "rand" attribute.
So we need to put this "rand" attribute here in front of all the register fields and the reason for this one is that this will allow us to randomize the register in order to make use of that value field inside the uvm_reg_field.
The fourth rule is this one: Field names shall be in all uppercase.
The reason behind this rule is to prevent any name collision with any fields declared under the uvm_reg.
And this rule also applies to functions and tasks that we will define in our register class.
So every function, every task that we define must have its name in all uppercase.
Taking into consideration these four rules, this is how our Control class should look like.
Our Control class extends from uvm_reg and it has inside these three register fields.
And all these fields are public, have the same name as the fields defined in the Aligner documentation, they have the "rand" attribute in front, and they are all in uppercase.
The fifth rule is this one: Field types are instantiated in the build() method of the containing register types.
This means that we need to define a build() function in which we create the instances of our register fields.
And one thing that might be confusing, this build() function is not really defined under the uvm_reg and we simply need to extend it.
We need to create this function for the first time in each class of our registers.
The next rule is this one: The build() method shall call the configure() method of all the field class properties.
Remember from the previous tutorial that our uvm_reg_field class has this very important function called configure(), in which we configure all the important properties of a field, and this rule tells us that we should call this configure() function in the build() function of the register.
So the build() function from our Control register class will look like this.
It will create the instances of all the fields and then it will call the configure() function for all these fields.
So these are the six rules that we will take into consideration in the next tutorial in which we will implement all the register classes.
But keep in mind that the "UVM User Guide" provides many other rules that you need to be aware.
So I strongly recommend you to read the documentation and understand what else is defined there.
Now let's look a little bit on the API of the uvm_reg class to be aware of what functions and tasks are defined here.
First of all, the uvm_reg, it's a child class of uvm_object, so it will inherit all the attributes of this class.
One important function of the uvm_reg class is its constructor new(), which has this signature.
It has the name of the instance.
This n_bits represents the width of the register in bits.
And the last argument is this has_coverage which is of type int and this one can take one of these predefined values.
We will go with this UVM_NO_COVERAGE as we don't implement the coverage for the registers right now, but just be aware that you have these fields to control the coverage in the register.
This new() constructor is the only function that we will use in the next tutorial, but let's go quickly through other functions and tasks which are available for us in the uvm_reg class.
Just like for the field, we have the predict() function and get_mirrored_value() in order to access the m_mirror fields from each of the registers fields inside the reg.
So these will work with the entire value of the register.
Then we have the set() and get() to control the desired values inside the uvm_reg_field(s).
We also have the reset() function to reset the register.
Next, we have these three very important tasks: write(), read(), and update().
And these tasks will allow us to start accesses on the register access interface, and in our case, this is the APB interface.
We discussed in the previous tutorial how this update() task work with the desired values in the register fields, but one important aspect for this update() task is that it makes use of this needs_update().
And what this needs_update() function does is to compare the mirrored value with the desired value.
And the update() task will start the access on the register access interface only if there is a difference between the mirror and the desired values.
We also have this get_n_bits() to return the number of bits of the register.
And two other important functions which are commonly used are these ones, get_fields() and get_field_by_name(), which allow us to get the fields of a register.
So these are the most commonly used functions and tasks from the uvm_reg class, but the API is quite large and I strongly encourage you to go through the documentation and see what else is there.
And the information that you need, you can find in the "UVM Class Reference" under the "Register Layer", "Register Model".
There is this chapter "Registers", and in here you will find the description of the API of this uvm_reg class.
And of course, the other source of information is the "UVM User Guide", and here there is a dedicated chapter under the "Using Register Layer Classes", "Constructing a Register Model", you have this chapter "Register Types".
And you can find here useful information and also the rules that we discussed in this tutorial.
One last thing to mention in this tutorial is that the "UVM User Guide" also provides some rules about the register packaging and we have this rule: Block types, and all the register, register file, and memory types they require, should be located in a separate package.
This means that we need to define a package cfs_algn_reg_pkg and in here we include all the files in which we will put the register class definitions.
That's it for this tutorial.
We discussed about the UVM register class and we talked about the rules that we need to be aware when we are defining register classes.
And finally we discussed about where you can find the documentation for this class.
In the next tutorial, we will put in practice the information that we learn about the uvm_reg_field class and uvm_reg class, and we will implement the model for our four registers inside the Aligner.
Thanks for watching and see you in the next tutorial.
Bye!
