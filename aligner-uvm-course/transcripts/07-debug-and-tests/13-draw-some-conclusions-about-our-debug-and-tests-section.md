# Draw some conclusions about our "Debug and Tests" section

*Chapter: Debug and tests · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to draw some conclusions about our "Debug and Tests" section.
First of all, congratulations to you for completing this section.
You now have all the knowledge required to build a verification environment from scratch.
In this section you acquired the last skill set that you needed in order to create tests and debug them.
So let's quickly go through all the things that you learned in this section.
First of all, we went through some debug techniques.
We discussed and implemented the UVM messages.
You now know how to control these UVM messages and this makes your life during debug much easier.
We also discussed about the UVM transactions and how this feature of the UVM library can help us when we are using directly the simulator from a specific vendor.
And in the last debug technique that we discussed we saw how usefull it is to track the source of the information for the data coming out of our model.
Also in this section, you learned how to organize the tests and in particular how to make use of inheritance from object-oriented programming to maximize the reuse of your code.
We rewrote two of our tests, our register access test and our random traffic test in order to truly make them random.
You also learned how to create a targeted test using only constraints.
Remember that you created the illegal RX traffic test by inheriting from our random traffic test only using constraints.
And with our updated tests, we found two RTL bugs.
There might be other bugs hidden inside the DUT and it's up to you to run these tests and find them.
And if you find these bugs, please share this information with us.
That's it for this tutorial.
I hope everything was clear for you throughout this section.
Thanks for watching and see you in the next tutorial.
Bye!
