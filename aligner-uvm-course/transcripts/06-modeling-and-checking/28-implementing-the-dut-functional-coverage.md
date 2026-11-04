# Implementing the DUT functional coverage

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to start implementing the DUT functional coverage.
Because this is quite a big task, we will not have time to implement all the required functional coverage for our Aligner RTL, but we are going to implement only the coverage for the split functionality.
And for this, we will have to add in our project a class which will hold the split information.
Then, in our environment configuration class we will have to add a field with which we will control if the coverage is instantiated or not in our environment.
Next, we will have to add our coverage component with the port through which it will receive from the model the split information.
In our model component we will have to update the align() task in order to collect that split information.
And finally in the environment we will have to add the coverage instance created in the build_phase() and connect the ports.
The starting point is the EDA Playground project called "DUT Functional Coverage - Practice" which we need to copy.
And let's resize the windows.
The first thing that we will implement is the coverage component.
So let's do this.
Now let's include this file in our Aligner package.
That's it.
And now let's declare the class.
And that's it.
Next, let's add in our environment configuration class a field called has_coverage with which we will control if the coverage is instantiated or not in the environment.
And that's it.
So we have here the getter and the setter.
In the constructor I set this has_coverage to value 1 and here I declared the field.
Now let's go to our environment class and instantiate the coverage based on this has_coverage field from the environment configuration class.
So that's the handler and now in build_phase() let's create the instance of the coverage.
And that's the instance of our coverage component and let's not forget to reset our coverage in the handle_reset() of the environment.
And that's it.
Here we must pay attention to check if the coverage is not null then we call this handle_reset() function.
Remember that this handler can be null if we set in the environment configuration class that has_coverage equal to 0.
Next let's add our class which will hold the split information.
First let's declare the file.
That's it and now let's include this file in our Aligner package.
That's it and now let's declare our class.
That's it, so our class is extending from uvm_object and in here I declared the five fields that we need in the coverage.
Next, let's add in our model component a port through which our model will send this split information and then in the align() task we can collect that information and send it through this port.
So that's the declaration of our port and now in the constructor let's create an instance of it.
That's it and now let's update our align() task in order to send this information.
So here after we did the split we can also collect the split information for the coverage.
That's it.
So in this info object I'm setting all the five fields that we need for the coverage and then I'm sending this information through our port.
Next, let's declare in our coverage component our port through which we will receive this split information and once we have that we can declare the coverage group.
So first let's declare our analysis implementation port.
That's the declaration and now let's create an instance of it in the constructor.
And now let's declare the associated write() function.
That's it.
And now let's declare our coverage group for the split information.
This is our empty cover group and now let's create an instance of it in the constructor.
That's it.
Now in write_in_split_info() let's call the sample() function.
That's it.
And now let's add the coverage points in our cover group.
These are the cover points and now let's add the cross between all these.
That's it.
So I added in the ignore bins all the illegal combinations between the fields from the Control register: OFFSET and SIZE.
But we have other illegal combinations which will never be hit in our coverage.
For example, we can never have md_offset equal to 1 and md_size equal to 3.
But we will not add in this tutorial all the illegal combinations of this cross.
Just keep in mind that there are others which should be added here.
Next, let's add our coverage2string() function in order to be able to print the coverage and we can take the function from our APB package for example.
So let's copy this part and adapt it.
That's it.
And now let's call this function in the report_phase().
And that's it.
Remember that in a real project we should never print the coverage as we have a graphical user interface to visualize the coverage there is no need for us to do something like this.
We are printing the coverage information only in the EDA Playground project in order to be able to see the coverage numbers.
Now the last thing that we have to do is to go in the environment class and connect the port from the model with the one from the coverage.
That's it.
And now let's try to run our test to see what coverage numbers we get in our report_phase().
Our simulation finished and now let's search for our coverage information in the log.
Here is the information printed from our coverage component.
So our cross only got 1.39% covered.
This is quite a low number, but remember that there are other combinations of bins which should be ignored from this cross.
That's it for this tutorial.
We managed to add the first element from the DUT functional coverage, the split information.
Remember that this is just the first step in implementing the DUT functional coverage.
To complete this, we need to extract all the coverage information from our Aligner specification and then implement it in the coverage.
But as you can see, this is quite a time-consuming task and there is no need for us to go in this tutorial through all the elements.
I just wanted to give you an idea of how this coverage can be collected and sampled in our coverage component.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
