<?php
// (c)Perez Karjee(www.aas9.in)
// Project Site www.aas9.in/zerocms
// Created March 2014
// die('before here');
require_once('db.kate.php');

$mysqli = new mysqli(MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DB);
if ( $mysqli->connect_errno ){
  die("There was an error connecting to the MySQL database.");
}



$user_id = (isset($_GET['user_id']) && ctype_digit($_GET['user_id'])) ?
    $_GET['user_id'] : '';

if (empty($user_id)) {
    $name = '';
    $email = '';
    $access_level = '';
} else {


  if (! ( $query = $mysqli->prepare("SELECT name, email, access_level FROM zero_users WHERE user_id=(?)") )){

    die('Preparing statement failed: (' . $mysqli->errno . ') ' . $mysqli->error);
  }

  if ( ! $query->bind_param("i", $user_id) ){
    die('Binding parameters failed: (' . $query->errno . ') ' . $query->error);
  }
  $query->execute();
  $result = $query->get_result();
  $row = $result->fetch_assoc();

  // die('answer='.print_r($row));
  $name = $row['name'];
  $email = $row['email'];
  $access_level = $row['access_level'];
  
}

include('header.kate.php');

if (empty($user_id)) {
    echo '<h1>Create Account</h1>';
} else {
    echo '<h1>Modify Account</h1>';
}
?>
<form method="post" action="zero_transact_user.php">
 <table>
  <tr>
   <td><label for="name">Full Name:</label></td>
   <td><input type="text" id="name" name="name" maxlength="100"
     value="<?php echo htmlspecialchars($name); ?>"/></td>
  </tr><tr>
   <td><label for="email">Email Address:</label></td>
   <td><input type="text" id="email" name="email" maxlength="100"
     value="<?php echo htmlspecialchars($email); ?>"/></td>
  </tr>
<?php


if (isset($_SESSION['access_level']) && $_SESSION['access_level'] == 3)
{
    echo '<tr><td>Access Level</td><td>';

    $sql = 'SELECT access_level, access_name FROM zero_access_levels ORDER BY access_level DESC';
    $result = mysqli_query($sql, $dbx) or die(mysql_error($dbx));

    while ($row = mysqli_fetch_array($result)) {
        echo '<input type="radio" id="acl_' . $row['access_level'] .
            '" name="access_level" value="' . $row['access_level'] . '"';

        if ($row['access_level'] == $access_level) {
            echo ' checked="checked"';
        }
        echo '/> <label for="acl_' . $row['access_level'] . '">' .
            $row['access_name'] . '</label><br/>';
    }
    mysqli_free_result($result);
    echo '</td></tr>';
}

if (empty($user_id)) {
?>
  <tr>
   <td><label for="password_1">Password:</label></td>
   <td><input type="password" id="password_1" name="password_1" maxlength="50"/>
   </td>
  </tr><tr>
   <td><label for="password_2">Confirm Password:</label></td>
   <td><input type="password" id="password_2" name="password_2" maxlength="50"/>
   </td>
  </tr><tr>
   <td> </td>
   <td>
    <input type="submit" name="action" value="Create Account"/>
   </td>
  </tr>
<?php
} else {
?>
  <tr>
   <td> </td>
   <td>
    <input type="hidden" name="user_id" value="<?php echo $user_id; ?>"/>
    <input type="submit" name="action" value="Modify Account"/>
   </td>
  </tr>
<?php
}
?>
 </table>
</form>
<?php
include 'footer.kate.php';
?>
