# UVM register field

*Chapter: Register model (RAL) · source: attached*

Hi, my name is Cristian Slav and in this tutorial we are going to talk about the UVM register field.
From the UVM documentation we get this definition for an UVM register field.
A field represents a set of bits that behave consistently as a single entity.
And if we look at the Control register, in our case a field it's for example the SIZE or OFFSET or CLR.
So we will model these fields as UVM register fields.
Regarding the reserved bits of the Control register, we could model also these as UVM register fields, but the UVM documentation gives us the possibility to leave these fields as unmodeled.
There is a small section in the "UVM User Guide" called "Reserved Fields" and in here there is a statement which allows us to not model these fields.
Reserved fields should be left unmodeled where they will be assumed to be read-only fields filled with zeros.
And this is the exact scenario in which we are with these reserved fields, part of the Control register, but also part of the other three registers in our case.
The other options that we get from the UVM documentation regarding the reserved fields is either to model them or to disable the checking for these fields by setting this set_compare() equal to 0.
But in our case we will go with the first option of not modeling them, but in later tutorials part of this section we will see that there is at least one advantage to also model these reserved fields.
Now let's look at the API of this uvm_reg_field class and discuss the most commonly used functions and fields from here.
First of all, uvm_reg_field is a child class of uvm_object, so it will inherit all the attributes of the uvm_object class.
Inside uvm_reg_field class, there are 4 fields for modeling some values of this field.
We have this public field called value and then we have these three private or local fields, mirrored, desired and reset.
And let's see how these four fields are used to model the behavior of a register field.
Let's take as an example the Control register, where we have these three fields, CLR, OFFSET, and SIZE.
And in this table, we have on each row these values, mirror, desired, value, and reset.
And each of the column of the table represents one instance of a register field.
So we have one instance for CLR, another one for OFFSET, and another one for SIZE.
And let's also see our DUT, our Aligner, which has inside the physical implementation of these three fields: CLR, OFFSET, and SIZE.
The first field that we are going to discuss is this mirrored, and this field represents our best guess of what's inside the RTL.
So what we think is the value of each register field inside our Aligner.
And let's see how this field is used.
So when we have a write access which reaches the APB interface of our Aligner, this write access has some data which will update the SIZE with value 1, OFFSET with value 0 and CLR with value 0 again.
And this write access will go to the Aligner, but also to our register model via the APB monitor and then via the predictor.
And when this is happening, the RTL will update its internal values of these fields, but also our model will update its mirrored value.
So in the instance of the SIZE register field, we'll have value 1, in the mirrored field for the OFFSET 0 and for the CLR 0.
And if there is no RTL bug, these values will mirror exactly the values inside our Aligner.
And during the read accesses, when we send a read access to the Aligner, the RTL will return some data for that read access and this read information will be sent to our model.
And our model will start to compare the mirrored value with whatever data was returned by the RTL and it will check that value and let's say that if there is a bug in RTL and it will return value 0 for the SIZE even though inside it should have been value 1, then our register model will automatically compare this and it will trigger an error if such a scenario is detected.
So this is how this mirrored value is used.
It will be updated during the write accesses and it will be used to check the value returned by the RTL during read accesses.
Because this mirrored field is a local field, it's a private field, we need some functions to access it.
And we have get_mirrored_value() function to get the value of this field and to set it we have the predict() function.
For fields which are updatable only by doing reads and writes on the register access interface, we don't really need to call this predict() function because this will be done automatically by our register model.
However, we need to call this predict() function, for example, for status registers.
So for registers which are updatable by the hardware itself.
And we need to call this predict() function in order to model also that value inside our environment.
The desired field, just like the name suggests, represents the value that we desire to have in our register field.
We have two functions as the getter and the setter for this field, and these are called get() and set().
The way you should use this desired value is in this way.
First you call the set() function to set some desired value for each of these fields.
So, in this example, we set the desired value for the SIZE to be equal to 2 and the desired value for the OFFSET to also be equal to 2.
And once we do this, we update the desired values for each of these fields.
And after that, we can call the update() task of the parent register, in our case, the Control.
And when we do this, the register model will trigger an APB write access with the correct data, which will update our fields with the values that we set in the desired field.
And once this APB access is completed, then the fields inside the DUT will be updated to the desired values and of course also our mirrored values will be equal then to the desired values that we set here.
The third field that we have is this value field and this is used during randomization.
This is the only public field and the reason why this is public is to allow us to apply constraints to it.
So in our case, for the Control register where we have some special relationship between OFFSET and SIZE, we can write such a constraint in order to generate every time legal values for these fields.
So when we randomize the Control register, these values will be generated, and for example, let's say that it is generated like so, 0, 0, and 4, and once we randomize the Control register, in the post_randomize() of each field, the value will be copied to the desired value.
So this 0 0 4 will be moved to the desired value.
And after that, we can call the update() task of the Control register and that will generate an APB write access with the write data generated based on the desired values from here.
The last field in our uvm_reg_field is this reset field.
As the name suggests, this keeps the reset value of a field and this is an associative array with the key type being a string.
The reason why this is an array is that you can have multiple reset values.
There are RTL implementations with multiple reset signals like hard, soft and so on, and for each of those resets you can set different reset values for your field.
The default key for this array is this "HARD" value, and this is set when you call the configure() function.
For the fields, part of the Control register, the reset values will be these ones, so CLR will be 0, OFFSET 0, and SIZE 1.
And the register field also has this reset() function.
And when you call this reset() function, the value inside this reset array will be moved to mirrored, desired, and value.
So this is the implementation of the reset() function inside uvm_reg_field class.
So after the reset, all these fields will be equal to whatever you configured in the m_reset associative array.
Normally you don't have to call this reset() function for each of the register field, you usually call the reset() function of the entire register block, and this in turn will call the reset() function of all the registers, and that one will call the reset() function of all the register fields, and of course you call that reset() function whenever you detect that also the RTL gets resetted.
There are a couple of other functions that you can use in order to access this m_reset.
So you have this has_reset(), get_reset(), and set_reset().
So these are the four fields inside the uvm_reg_field class, which handles in some way the data.
One other important field inside uvm_reg_field is this local field called m_access.
The type of this field is string, and this one determines the behavior of the register field during read and write accesses.
And it is modeling this access right here.
So for the CLR, we have the write-only access, for the OFFSET, we have the read-write, and also for the SIZE.
There are some predefined values for this access field, and you can find these values in the UVM documentation.
In the User Guide, there is this Table 7, which lists all the predefined values for this access field.
In the Aligner case we have four different access types, so we have read- only, read-write, write- one-clear and write-only.
So these are the values that we will use in our environment, but as you can see there are many more other predefined fields.
And when you look on this table, it's important for you to understand what would be the effect of that access value when you write or you read a register field.
So for the write access, you get the effect in this column, and for the read access, you get the effect on this column.
The value of this access field is usually configured when you call this configure() function, but you also have two other functions to access this field called get_access() and set_access(), the getter and the setter.
There are two other functions inside the uvm_reg_field which are commonly used.
This get_lsb_pos() which will return you the least significant bit position for a register field.
So in our case for the SIZE will return 0, for the OFFSET will return 8 and for the CLR will return 16.
And another function which is used often is this get_n_bits() which will return the width in bits of each field.
So for the SIZE this function will return 3, for the OFFSET 2 and for CLR 1.
Now let's look at this configure() function.
This is quite an important function as you need to call this configure() function for each of the register field when you create that instance.
The first argument it's a pointer to the parent register.
The second argument size it's the number of bits of a register field.
So, for example, for the OFFSET field the value of this size argument will be 2 as it has a width of 2 bits. lsb_pos is the least significant bit position, so we will use value 0 for the SIZE, value 8 for the OFFSET, and value 16 for the CLR.
Access is that m_access field that we discussed, so whatever value you configure for this access argument of the configure() function will end up in this m_access field.
This volatile value is usually configured with value 0.
We only set this to 1 for fields which are very volatile inside the RTL.
So for example, there might be some status register fields which are changing quite fast, and it would be difficult for us to model those fields inside our environment.
And because we don't really want to trigger false errors when we are reading that register field, we set this to 1.
Just keep in mind that when you set this volatile to 1, there will be no checking during the read accesses for that register field.
Reset is the value which will be set in this m_reset with the key "HARD", but this will happen only if you set also this has_reset to 1. is_rand controls the randomization for this value field.
We usually set this to 1, but if you want some field not to be randomized when you call the randomize() function of the register, you simply set this to 0.
The last argument of this configure function, individually_accessible, you should set it to 1 when the protocol for accessing the registers allows you to access only one single field during an access.
But in our case for the Aligner, we have the APB protocol to access the registers, and it is not possible with an APB transaction to access only the OFFSET field.
When we are sending a write transaction, we are accessing the entire Control register, not only just one field.
And for this reason, we will use only value 0 for this argument.
So these are the most commonly used fields and functions from this uvm_reg_field class, but the API is quite large, and I strongly recommend you to look through the documentation to see what else is there.
And you can find more information in the "UVM Class Reference" manual under "Register Layer", "Register Model", there is this "Fields" chapter, and in here you can find the API of the uvm_reg_field class.
And another source of information for you is the "UVM User's Guide".
Also here there is a dedicated chapter for the fields under the "UVM Register Layer Classes". "Constructing a Register Model", you have here "Field Types" and you can find here more useful information about the uvm_reg_field class and also if you scroll down you will find that table 7 that we discussed about the access field.
That's it for this tutorial.
We discussed about the uvm_reg_field class and its API and I also point you again to the documentation.
The next tutorial will also be a lecture about the UVM register and only after that we will have a practice tutorial where we will put all this information into our project.
Thanks for watching and see you in the next tutorial.
Bye!
